package com.amzur.pixorex.keycloak.otp;

import java.util.Locale;
import java.util.Optional;
import java.util.regex.Pattern;

/** Parses what the user typed on the identifier page into an email or an E.164 phone number. */
public final class Identifiers {

    public enum Type { EMAIL, PHONE }

    public record Identifier(Type type, String value) {
    }

    private static final Pattern EMAIL = Pattern.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");
    private static final Pattern E164 = Pattern.compile("^\\+[1-9]\\d{7,14}$");

    private Identifiers() {
    }

    public static Optional<Identifier> parse(String raw, boolean allowPhone) {
        if (raw == null) {
            return Optional.empty();
        }
        String value = raw.trim();
        if (value.isEmpty() || value.length() > 254) {
            return Optional.empty();
        }
        if (value.indexOf('@') >= 0) {
            String email = value.toLowerCase(Locale.ROOT);
            return EMAIL.matcher(email).matches() ? Optional.of(new Identifier(Type.EMAIL, email)) : Optional.empty();
        }
        if (!allowPhone) {
            return Optional.empty();
        }
        String phone = value.replaceAll("[\\s().-]", "");
        if (phone.startsWith("00")) {
            phone = "+" + phone.substring(2);
        }
        return E164.matcher(phone).matches() ? Optional.of(new Identifier(Type.PHONE, phone)) : Optional.empty();
    }
}
