package com.amzur.pixorex.keycloak.sms;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class SmsTest {

    @Test
    void givenACode_whenTheSmsIsWritten_thenItEndsWithTheDomainBoundAutofillLine() {
        assertEquals("Pixorex sign-in code: 482913. It expires in 5 minutes. Never share it.\n\n@auth.pixorex.example #482913",
                SmsText.signInCode("482913", 5, "auth.pixorex.example"));
    }

    @Test
    void givenAJsonTemplate_whenRendered_thenValuesAreEscaped() {
        String body = SmsRequestTemplate.render("{\"to\":\"{to}\",\"n\":\"{to_digits}\",\"from\":\"{sender}\",\"text\":\"{text}\"}",
                "json", "+15550100001", "PIXRX", "line \"1\"\nline 2");
        assertEquals("{\"to\":\"+15550100001\",\"n\":\"15550100001\",\"from\":\"PIXRX\",\"text\":\"line \\\"1\\\"\\nline 2\"}", body);
    }

    @Test
    void givenAFormTemplate_whenRendered_thenValuesAreUrlEncoded() {
        String body = SmsRequestTemplate.render("to={to}&msg={text}", "form", "+15550100001", null, "a b&c");
        assertEquals("to=%2B15550100001&msg=a+b%26c", body);
        assertEquals("application/x-www-form-urlencoded", SmsRequestTemplate.contentType("form"));
        assertEquals("application/json", SmsRequestTemplate.contentType("json"));
    }
}
