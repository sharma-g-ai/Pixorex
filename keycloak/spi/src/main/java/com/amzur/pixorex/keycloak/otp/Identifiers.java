package com.amzur.pixorex.keycloak.otp;

import java.util.Locale;
import java.util.Optional;
import java.util.regex.Pattern;

/** Parses what the user typed on the identifier page. Sign-in is by email only, on the web and the mobile app. */
public final class Identifiers {

    private static final Pattern EMAIL = Pattern.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");

    private Identifiers() {
    }

    /** The email, trimmed and lowercased, or empty when the text is not an email. */
    public static Optional<String> email(String raw) {
        if (raw == null) {
            return Optional.empty();
        }
        String value = raw.trim().toLowerCase(Locale.ROOT);
        if (value.isEmpty() || value.length() > 254 || !EMAIL.matcher(value).matches()) {
            return Optional.empty();
        }
        return Optional.of(value);
    }
}
