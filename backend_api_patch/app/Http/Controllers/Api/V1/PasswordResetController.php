<?php

namespace App\Http\Controllers\Api\V1;

use App\Mail\PasswordResetOtpMail;
use App\Models\PasswordResetOtp;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;

/**
 * AUTH-5 .. AUTH-8 — the web's forgot-password flow (Auth\ForgotPasswordController)
 * without the PHP session: the app sends the email with every step.
 *
 *   forgot-password {email}                 → emails a 6-digit OTP
 *   verify-otp      {email, otp}            → returns a one-time reset_token
 *   resend-otp      {email}                 → new OTP (old one expires)
 *   reset-password  {email, reset_token, password, password_confirmation}
 *
 * Rules are the web's (config/password_reset_otp.php): OTP valid 10 min, max 5
 * wrong tries, reset token valid 15 min, password >= 6 with letters + numbers.
 * Like the web, an unknown/inactive email is reported as such.
 * Extra protection: a successful reset signs the user out of every device.
 */
class PasswordResetController extends ApiController
{
    private const NOT_FOUND = 'We could not find an active account with that email address.';

    public function forgot(Request $request)
    {
        $email = $this->emailInput($request);
        $user = $this->activeUser($email);

        $this->issueAndSend($user, $email, 'email', 'Unable to send the verification email right now. Please try again in a few minutes.');

        return $this->ok($this->challengeInfo($email), 'A verification code has been sent to your email.');
    }

    public function resend(Request $request)
    {
        $email = $this->emailInput($request);
        $user = $this->activeUser($email);

        $this->issueAndSend($user, $email, 'otp', 'Unable to resend the verification email right now. Please try again in a few minutes.');

        return $this->ok($this->challengeInfo($email), 'A new verification code has been sent to your email.');
    }

    public function verify(Request $request)
    {
        $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'otp' => ['required', 'digits:6'],
        ], [
            'otp.required' => 'Please enter the 6-digit verification code.',
            'otp.digits' => 'The OTP must be exactly 6 digits.',
        ]);

        $email = strtolower(trim($request->input('email')));
        $user = $this->activeUser($email);

        $record = PasswordResetOtp::where('user_id', $user->id)->where('email', $email)->latest('id')->first();

        if (!$record) {
            throw ValidationException::withMessages(['otp' => 'Please request a verification code first.']);
        }
        if ($record->isVerified()) {
            throw ValidationException::withMessages(['otp' => 'This OTP has already been used. Please request a new one.']);
        }

        $max = (int) config('password_reset_otp.max_attempts', 5);

        if ($record->hasExceededAttempts($max)) {
            throw ValidationException::withMessages(['otp' => 'Too many attempts. Please try again later.']);
        }
        if ($record->isExpired()) {
            throw ValidationException::withMessages(['otp' => 'This OTP has expired. Please request a new OTP.']);
        }

        if (!Hash::check($request->input('otp'), $record->otp)) {
            $record->increment('attempts');

            if ($record->fresh()->hasExceededAttempts($max)) {
                throw ValidationException::withMessages(['otp' => 'Too many attempts. Please try again later.']);
            }

            throw ValidationException::withMessages(['otp' => 'The OTP you entered is incorrect.']);
        }

        $minutes = (int) config('password_reset_otp.reset_token_expire_minutes', 15);
        $token = Str::random(64);

        $record->forceFill([
            'verified_at' => now(),
            'reset_token' => $token,
            'reset_token_expires_at' => now()->addMinutes($minutes),
            'reset_token_used_at' => null,
        ])->save();

        return $this->ok([
            'reset_token' => $token,
            'expires_in_seconds' => $minutes * 60,
            'password_min_length' => (int) config('password_reset_otp.password_min_length', 6),
        ], 'OTP verified successfully. Please create a new password.');
    }

    public function reset(Request $request)
    {
        $min = (int) config('password_reset_otp.password_min_length', 6);

        $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'reset_token' => ['required', 'string', 'size:64'],
            'password' => ['required', 'confirmed', Password::min($min)->letters()->numbers()],
        ], [
            'password.required' => 'Please enter a new password.',
            'password.confirmed' => 'Confirm password does not match.',
            'password.min' => "Password must be at least {$min} characters.",
        ]);

        $email = strtolower(trim($request->input('email')));
        $token = (string) $request->input('reset_token');
        $expired = 'Your password reset session has expired. Please try again.';

        $user = User::whereRaw('LOWER(email) = ?', [$email])->first();

        if (!$user || (int) $user->active_status !== 1) {
            throw ValidationException::withMessages(['email' => self::NOT_FOUND]);
        }

        $record = PasswordResetOtp::where('user_id', $user->id)
            ->where('email', $email)
            ->where('reset_token', $token)
            ->whereNotNull('verified_at')
            ->whereNull('reset_token_used_at')
            ->latest('id')
            ->first();

        if (!$record || !$record->isResetTokenValid($token)) {
            throw ValidationException::withMessages(['reset_token' => $expired]);
        }

        DB::transaction(function () use ($user, $record, $request) {
            $user->forceFill([
                'password' => Hash::make($request->input('password')),
                'remember_token' => Str::random(60),
            ])->save();

            $record->forceFill([
                'reset_token_used_at' => now(),
                'reset_token' => null,
                'reset_token_expires_at' => null,
            ])->save();

            PasswordResetOtp::where('user_id', $user->id)
                ->whereNull('reset_token_used_at')
                ->where('id', '!=', $record->id)
                ->update(['expires_at' => now(), 'reset_token' => null, 'reset_token_expires_at' => null]);

            // Not in the web (it has no API tokens): sign the user out everywhere.
            $user->tokens()->delete();
        });

        return $this->ok([], 'Password reset successfully. Please login with your new password.');
    }

    // ------------------------------------------------------------- internals

    private function emailInput(Request $request): string
    {
        $request->validate([
            'email' => ['required', 'email', 'max:255'],
        ], [
            'email.required' => 'Please enter your registered email address.',
            'email.email' => 'Please enter a valid email address.',
        ]);

        return strtolower(trim($request->input('email')));
    }

    private function activeUser(string $email): User
    {
        $user = User::whereRaw('LOWER(email) = ?', [$email])->where('active_status', 1)->first();

        if (!$user) {
            throw ValidationException::withMessages(['email' => self::NOT_FOUND]);
        }

        return $user;
    }

    /**
     * web: ForgotPasswordController::issueAndSendOtp — expire any open OTP, drop
     * unused reset tokens, store a hashed 6-digit OTP, email it. The plain OTP is
     * never logged or returned.
     */
    private function issueAndSend(User $user, string $email, string $errorField, string $errorMessage): void
    {
        $minutes = (int) config('password_reset_otp.otp_expire_minutes', 10);
        $plain = (string) random_int(100000, 999999);

        DB::transaction(function () use ($user, $email, $plain, $minutes) {
            PasswordResetOtp::where('user_id', $user->id)
                ->whereNull('verified_at')
                ->where('expires_at', '>', now())
                ->update(['expires_at' => now()]);

            PasswordResetOtp::where('user_id', $user->id)
                ->whereNotNull('verified_at')
                ->whereNull('reset_token_used_at')
                ->whereNotNull('reset_token')
                ->update(['reset_token' => null, 'reset_token_expires_at' => null]);

            PasswordResetOtp::create([
                'user_id' => $user->id,
                'email' => $email,
                'otp' => Hash::make($plain),
                'expires_at' => now()->addMinutes($minutes),
                'attempts' => 0,
            ]);
        });

        try {
            Mail::to($email)->send(new PasswordResetOtpMail([
                'name' => $user->name ?: 'Admin',
                'otp' => $plain,
                'expire_minutes' => $minutes,
                'subject' => 'Your Password Reset OTP - Rosenthal Barbershop',
            ]));
        } catch (\Throwable $e) {
            report($e);

            $message = $errorMessage;
            if (config('app.debug')) {
                $message .= ' (' . $e->getMessage() . ')';
            }

            throw ValidationException::withMessages([$errorField => $message]);
        }
    }

    private function challengeInfo(string $email): array
    {
        return [
            'masked_email' => $this->maskEmail($email),
            'otp_length' => 6,
            'expires_in_seconds' => (int) config('password_reset_otp.otp_expire_minutes', 10) * 60,
        ];
    }

    private function maskEmail(string $email): string
    {
        if (!str_contains($email, '@')) {
            return 'your email';
        }

        [$local, $domain] = explode('@', $email, 2);
        $visible = max(1, (int) floor(strlen($local) / 3));

        return substr($local, 0, $visible) . str_repeat('*', max(1, strlen($local) - $visible)) . '@' . $domain;
    }
}
