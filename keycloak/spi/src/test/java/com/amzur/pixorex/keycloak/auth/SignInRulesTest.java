package com.amzur.pixorex.keycloak.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;

import org.junit.jupiter.api.Test;
import org.keycloak.models.RealmModel;
import org.keycloak.models.RoleModel;
import org.keycloak.models.UserModel;

import com.amzur.pixorex.keycloak.otp.Channel;

class SignInRulesTest {

    private final Map<String, String> clientRoles = PixorexAppGateAuthenticator.parse(PixorexAppGateAuthenticatorFactory.DEFAULT_CLIENT_ROLES);

    @Test
    void givenTheDefaultMapping_whenParsed_thenEachAppNeedsTheRoleOfTheSameName() {
        assertEquals(Map.of("pixorex-web", "pixorex-web", "pixorex-mobile", "pixorex-mobile"), clientRoles);
        assertEquals(Map.of("a", "b"), PixorexAppGateAuthenticator.parse(" a = b , broken, =x,"));
    }

    @Test
    void givenATechnicianOnTheWebDashboard_whenDenied_thenTheyAreToldToUseTheMobileApp() {
        RealmModel realm = realmWithRoles();
        UserModel technician = userWith(realm, "pixorex-mobile");
        assertEquals("pixorexUseMobileApp", PixorexAppGateAuthenticator.deniedMessage(realm, technician, "pixorex-web", clientRoles));
    }

    @Test
    void givenAnAdminOnTheMobileApp_whenDenied_thenTheyAreToldToUseTheWebDashboard() {
        RealmModel realm = realmWithRoles();
        UserModel admin = userWith(realm, "pixorex-web");
        assertEquals("pixorexUseWebApp", PixorexAppGateAuthenticator.deniedMessage(realm, admin, "pixorex-mobile", clientRoles));
    }

    @Test
    void givenAUserWithNoAppRole_whenDenied_thenTheMessageIsGeneric() {
        RealmModel realm = realmWithRoles();
        UserModel nobody = userWith(realm);
        assertEquals("pixorexNoAccess", PixorexAppGateAuthenticator.deniedMessage(realm, nobody, "pixorex-web", clientRoles));
    }

    @Test
    void givenAnInvitedAdmin_whenTheEmailCodeSucceeds_thenTheEmailBecomesVerified() {
        UserModel user = mock(UserModel.class);
        when(user.isEmailVerified()).thenReturn(false);
        assertTrue(PixorexOtpAuthenticator.activate(user, Channel.EMAIL));
        verify(user).setEmailVerified(true);
    }

    @Test
    void givenAnInvitedTechnician_whenTheSmsCodeSucceeds_thenThePhoneBecomesVerified() {
        UserModel user = mock(UserModel.class);
        when(user.getFirstAttribute("phone_verified")).thenReturn("false");
        assertTrue(PixorexOtpAuthenticator.activate(user, Channel.SMS));
        verify(user).setSingleAttribute("phone_verified", "true");
    }

    @Test
    void givenAnActiveUser_whenTheCodeSucceeds_thenNothingChanges() {
        UserModel user = mock(UserModel.class);
        when(user.isEmailVerified()).thenReturn(true);
        when(user.getFirstAttribute("phone_verified")).thenReturn("true");
        assertFalse(PixorexOtpAuthenticator.activate(user, Channel.EMAIL));
        assertFalse(PixorexOtpAuthenticator.activate(user, Channel.SMS));
        verify(user, never()).setEmailVerified(anyBoolean());
        verify(user, never()).setSingleAttribute(any(), any());
    }

    private static RealmModel realmWithRoles() {
        RealmModel realm = mock(RealmModel.class);
        for (String name : new String[] { "pixorex-web", "pixorex-mobile" }) {
            RoleModel role = mock(RoleModel.class);
            when(role.getName()).thenReturn(name);
            when(realm.getRole(name)).thenReturn(role);
        }
        return realm;
    }

    private static UserModel userWith(RealmModel realm, String... roles) {
        UserModel user = mock(UserModel.class);
        for (String role : roles) {
            RoleModel model = realm.getRole(role);
            when(user.hasRole(model)).thenReturn(true);
        }
        return user;
    }
}
