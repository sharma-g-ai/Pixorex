package com.amzur.pixorex.keycloak.otp;

import java.util.Map;

/**
 * Code policy. Defaults follow docs/keycloak.md §4.3 and are overridable per execution in the admin console.
 */
public record OtpSettings(int codeLength, int ttlSeconds, int resendCooldownSeconds, int maxSends, int sendWindowSeconds) {

    public static final String CODE_LENGTH = "codeLength";
    public static final String TTL_SECONDS = "ttlSeconds";
    public static final String RESEND_COOLDOWN_SECONDS = "resendCooldownSeconds";
    public static final String MAX_SENDS = "maxSends";
    public static final String SEND_WINDOW_SECONDS = "sendWindowSeconds";

    public static final OtpSettings DEFAULTS = new OtpSettings(6, 300, 60, 5, 900);

    public static OtpSettings from(Map<String, String> config) {
        if (config == null) {
            return DEFAULTS;
        }
        return new OtpSettings(
                read(config, CODE_LENGTH, DEFAULTS.codeLength, 6, 8),
                read(config, TTL_SECONDS, DEFAULTS.ttlSeconds, 30, 900),
                read(config, RESEND_COOLDOWN_SECONDS, DEFAULTS.resendCooldownSeconds, 10, 600),
                read(config, MAX_SENDS, DEFAULTS.maxSends, 1, 50),
                read(config, SEND_WINDOW_SECONDS, DEFAULTS.sendWindowSeconds, 60, 86400));
    }

    public int ttlMinutes() {
        return Math.max(1, (ttlSeconds + 59) / 60);
    }

    private static int read(Map<String, String> config, String key, int fallback, int min, int max) {
        String value = config.get(key);
        if (value == null || value.isBlank()) {
            return fallback;
        }
        try {
            int parsed = Integer.parseInt(value.trim());
            return parsed < min || parsed > max ? fallback : parsed;
        } catch (NumberFormatException e) {
            return fallback;
        }
    }
}
