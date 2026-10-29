<?php

namespace App\Services\Api;

/**
 * Money leaves the API as a decimal string with exactly two decimals ("25.00"),
 * never as a float, so the app cannot show 24.999999 or lose a cent.
 */
class Money
{
    public static function str($value): string
    {
        return number_format((float) $value, 2, '.', '');
    }
}
