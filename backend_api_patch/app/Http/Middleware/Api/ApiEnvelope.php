<?php

namespace App\Http\Middleware\Api;

use App\Services\Api\UserPresenter;
use Closure;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Throwable;

/**
 * Turns every exception thrown inside an API request into the standard envelope
 *   { "status": 0, "message": "...", "errors": {...}, "request_id": "..." }
 * so the app has exactly one error shape to handle. The web exception handler
 * (app/Exceptions/Handler.php) is not touched.
 */
class ApiEnvelope
{
    public function handle(Request $request, Closure $next)
    {
        return $this->withPermissionsVersion($request, $this->run($request, $next));
    }

    /**
     * Every answer to a signed-in user carries `X-Permissions-Version`. The app compares it
     * with the one it holds and quietly re-reads /bootstrap when an admin changed this
     * user's role or permissions, so no sign-out is needed. Errors carry it too (a 403
     * is exactly when the app wants to know). Never allowed to break the real answer.
     */
    protected function withPermissionsVersion(Request $request, $response)
    {
        try {
            $user = $request->user();
            if ($user && (int) $user->active_status === 1) {
                $response->headers->set('X-Permissions-Version', UserPresenter::version($user, true));
            }
        } catch (Throwable $e) {
            report($e);
        }

        return $response;
    }

    protected function run(Request $request, Closure $next)
    {
        try {
            $response = $next($request);
        } catch (Throwable $e) {
            return $this->render($e, $request);
        }

        // Laravel's router pipeline already converts an exception thrown by a
        // controller or inner middleware into a response (via the web handler) and
        // attaches the original exception to it. Re-render those in our envelope.
        $exception = $response->exception ?? null;
        if ($exception instanceof Throwable) {
            return $this->render($exception, $request);
        }

        return $response;
    }

    protected function render(Throwable $e, Request $request)
    {
        $body = ['status' => 0, 'message' => 'Something went wrong. Please try again.'];
        $http = 500;

        if ($e instanceof ValidationException) {
            $http = 422;
            $errors = $e->errors();
            $body['message'] = (string) (collect($errors)->flatten()->first() ?: 'The given data was invalid.');
            $body['errors'] = $errors;
        } elseif ($e instanceof AuthenticationException) {
            $http = 401;
            $body['message'] = 'Unauthenticated.';
        } elseif ($e instanceof AuthorizationException || $e instanceof AccessDeniedHttpException) {
            $http = 403;
            $body['message'] = $e->getMessage() ?: 'This action is unauthorized.';
        } elseif ($e instanceof ModelNotFoundException) {
            $http = 404;
            $body['message'] = 'Not found.';
        } elseif ($e instanceof NotFoundHttpException) {
            $http = 404;
            $body['message'] = 'Endpoint not found.';
        } elseif ($e instanceof MethodNotAllowedHttpException) {
            $http = 405;
            $body['message'] = 'Method not allowed.';
        } elseif ($e instanceof HttpExceptionInterface) {
            $http = $e->getStatusCode();
            $body['message'] = $http >= 500
                ? 'Something went wrong. Please try again.'
                : ($e->getMessage() ?: 'Request could not be completed.');
        } else {
            report($e);
        }

        $body['request_id'] = $request->attributes->get('request_id');

        if ($http === 500 && config('app.debug')) {
            $body['debug'] = [
                'exception' => get_class($e),
                'message' => $e->getMessage(),
                'at' => basename($e->getFile()) . ':' . $e->getLine(),
            ];
        }

        $headers = $e instanceof HttpExceptionInterface ? $e->getHeaders() : [];

        return response()->json($body, $http, $headers);
    }
}
