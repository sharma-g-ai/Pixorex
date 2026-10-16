package com.amzur.pixorex.keycloak.otp;

/** Destinations shown on screen and in logs: {@code r••••@example.com}, {@code •••• 4821}. */
public final class Masking {

    private static final String DOTS = "\u2022\u2022\u2022\u2022";

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

    public static String phone(String phone) {
        if (phone == null) {
            return "";
        }
        String digits = phone.replaceAll("\\D", "");
        return DOTS + " " + (digits.length() <= 4 ? digits : digits.substring(digits.length() - 4));
    }

    public static String destination(Channel channel, String destination) {
        return channel == Channel.SMS ? phone(destination) : email(destination);
    }
}
