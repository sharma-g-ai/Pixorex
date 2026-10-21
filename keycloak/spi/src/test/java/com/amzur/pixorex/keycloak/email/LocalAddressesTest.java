package com.amzur.pixorex.keycloak.email;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class LocalAddressesTest {

    @Test
    void demoAndPixorexLocalAreSynthetic() {
        assertTrue(LocalAddresses.isSynthetic("ea@demo.local"));
        assertTrue(LocalAddresses.isSynthetic("EA@Demo.Local"));
        assertTrue(LocalAddresses.isSynthetic("sms+15550100001@pixorex.local"));
    }

    @Test
    void realInboxesAreNotSynthetic() {
        assertFalse(LocalAddresses.isSynthetic("iswarya.kolimalla@amzur.com"));
        assertFalse(LocalAddresses.isSynthetic("someone@example.com"));
        assertFalse(LocalAddresses.isSynthetic(null));
        assertFalse(LocalAddresses.isSynthetic(""));
        assertFalse(LocalAddresses.isSynthetic("not-an-email"));
    }
}
