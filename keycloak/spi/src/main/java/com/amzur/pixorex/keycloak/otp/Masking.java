package com.amzur.pixorex.keycloak.otp;

/** Destinations shown on screen and in logs: {@code r••••@example.com}. */
public final class Masking {

    private static final String DOTS = "••••";

    private Masking() {
    }

    public static String email(String email) {
        if (email == null) {
            return "";
        }
        int at = email.indexOf('@');
        if (at <= 0) {
            return DOTS;
        }
        return email.charAt(0) + DOTS + email.substring(at);
    }
}
