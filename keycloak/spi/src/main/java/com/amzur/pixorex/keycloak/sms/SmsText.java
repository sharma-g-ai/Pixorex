package com.amzur.pixorex.keycloak.sms;

/**
 * SMS body with the domain-bound line ({@code @host #code}) that lets iOS and Android offer one-tap autofill.
 */
public final class SmsText {

    private SmsText() {
    }

    public static String signInCode(String code, int ttlMinutes, String host) {
        String minutes = ttlMinutes == 1 ? "1 minute" : ttlMinutes + " minutes";
        return "Pixorex sign-in code: " + code + ". It expires in " + minutes + ". Never share it.\n\n@" + host + " #" + code;
    }
}
