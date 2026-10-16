package com.amzur.pixorex.keycloak.auth;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.keycloak.authentication.AuthenticatorFactory;
import org.keycloak.models.AuthenticationExecutionModel.Requirement;

class PixorexIdentifierAuthenticatorFactoryTest {

    @Test
    void givenEveryPixorexStep_whenRegistered_thenIdsMatchTheRealmFlow() {
        List<AuthenticatorFactory> factories = List.of(new PixorexIdentifierAuthenticatorFactory(), new PixorexAppGateAuthenticatorFactory(),
                new PixorexLockCheckAuthenticatorFactory(), new PixorexChannelAuthenticatorFactory(), new PixorexOtpAuthenticatorFactory());
        assertEquals(List.of("pixorex-identifier", "pixorex-app-gate", "pixorex-lock-check", "pixorex-channel", "pixorex-otp"),
                factories.stream().map(AuthenticatorFactory::getId).toList());
        for (AuthenticatorFactory factory : factories) {
            assertArrayEquals(new Requirement[] { Requirement.REQUIRED, Requirement.DISABLED }, factory.getRequirementChoices());
            assertFalse(factory.isUserSetupAllowed());
            assertFalse(factory.create(null).requiresUser(), factory.getId() + " must handle unknown identifiers itself");
        }
    }

    @Test
    void givenTheOtpStep_whenBruteForceCountsFailures_thenItReportsTheOtpCategory() {
        assertEquals("otp", new PixorexOtpAuthenticatorFactory().getReferenceCategory());
        assertTrue(new PixorexOtpAuthenticatorFactory().isConfigurable());
    }

    @Test
    void givenTheOtherSteps_whenTheyFail_thenTheyAreNeverCountedAsCredentialFailures() {
        assertNull(new PixorexIdentifierAuthenticatorFactory().getReferenceCategory());
        assertNull(new PixorexAppGateAuthenticatorFactory().getReferenceCategory());
        assertNull(new PixorexLockCheckAuthenticatorFactory().getReferenceCategory());
        assertNull(new PixorexChannelAuthenticatorFactory().getReferenceCategory());
        assertFalse(new PixorexLockCheckAuthenticatorFactory().isConfigurable());
    }

    @Test
    void givenASession_whenCreated_thenReturnsTheIdentifierAuthenticator() {
        assertInstanceOf(PixorexIdentifierAuthenticator.class, new PixorexIdentifierAuthenticatorFactory().create(null));
    }
}
