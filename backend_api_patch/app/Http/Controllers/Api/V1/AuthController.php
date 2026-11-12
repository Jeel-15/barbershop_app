<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\User;
use App\Services\Api\UserPresenter;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AuthController extends ApiController
{
    /**
     * Same rules as the web admin login: email + password, deactivated
     * accounts are refused. (The web's phone-number branch queries a
     * `contact_no` column that does not exist here, so it is email only.)
     */
    public function login(Request $request)
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:80'],
        ]);

        $user = User::where('email', $data['email'])->first();

        // Always run one hash check so "unknown email" and "wrong password"
        // take the same time and cannot be told apart.
        $hash = $user ? $user->password : '$2y$10$UOZ8xsaH2HzIgwxSkNL3pOR3D4V9MJSc8JRGBIpFGuh0SPqB1u8Xi';
        $valid = Hash::check($data['password'], $hash);

        if (!$user || !$valid) {
            return $this->fail('Invalid email or password.', 401);
        }

        if ((int) $user->active_status !== 1) {
            return $this->fail('This account is deactivated. Please reach out to the support team.', 403);
        }

        $token = $user->createToken(
            $data['device_name'] ?? 'mobile-app',
            ['*'],
            now()->addDays((int) config('api_v1.token_days', 30))
        );

        // Keep only the newest N devices signed in.
        $stale = $user->tokens()->orderByDesc('id')->pluck('id')->slice((int) config('api_v1.max_devices', 5));
        if ($stale->isNotEmpty()) {
            $user->tokens()->whereIn('id', $stale->values())->delete();
        }

        return $this->ok([
            'token' => $token->plainTextToken,
            'token_type' => 'Bearer',
            'expires_at' => optional($token->accessToken->expires_at)->toIso8601String(),
            'user' => $presented = UserPresenter::make($user),
            'permissions_version' => $presented['permissions_version'],
        ], 'You have successfully logged in.');
    }

    public function me(Request $request)
    {
        $presented = UserPresenter::make($request->user());

        return $this->ok([
            'user' => $presented,
            'permissions_version' => $presented['permissions_version'],
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return $this->ok([], 'You have been logged out.');
    }

    public function logoutAll(Request $request)
    {
        $request->user()->tokens()->delete();

        return $this->ok([], 'You have been logged out on all devices.');
    }
}
