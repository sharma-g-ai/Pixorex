package com.amzur.pixorex.keycloak.sms;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * Fills the provider request body. Placeholders: {to} (E.164), {to_digits} (no plus sign), {sender}, {text}.
 * Values are JSON-escaped for {@code json} and URL-encoded for {@code form}.
 */
public final class SmsRequestTemplate {

    public static final String JSON = "json";
    public static final String FORM = "form";

    private SmsRequestTemplate() {
    }

    public static String render(String template, String format, String to, String sender, String text) {
        String digits = to.replaceAll("\\D", "");
        return template
                .replace("{to_digits}", encode(format, digits))
                .replace("{to}", encode(format, to))
                .replace("{sender}", encode(format, sender == null ? "" : sender))
                .replace("{text}", encode(format, text));
    }

    public static String contentType(String format) {
        return FORM.equals(format) ? "application/x-www-form-urlencoded" : "application/json";
    }

    private static String encode(String format, String value) {
        return FORM.equals(format) ? URLEncoder.encode(value, StandardCharsets.UTF_8) : jsonEscape(value);
    }

    static String jsonEscape(String value) {
        StringBuilder out = new StringBuilder(value.length() + 8);
        for (char c : value.toCharArray()) {
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> {
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
                }
            }
        }
        return out.toString();
    }
}
