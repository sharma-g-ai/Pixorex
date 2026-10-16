package com.amzur.pixorex.keycloak.auth;

import java.util.HashMap;
import java.util.Map;

import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.Authenticator;
import org.keycloak.events.Errors;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.RoleModel;
import org.keycloak.models.UserModel;

public class PixorexAppGateAuthenticator implements Authenticator {

    static final String WEB_CLIENT = "pixorex-web";
    static final String MOBILE_CLIENT = "pixorex-mobile";

    @Override
    public void authenticate(AuthenticationFlowContext context) {
        UserModel user = context.getUser();
        if (user == null) {
            context.success();
            return;
        }
        Map<String, String> clientRoles = parse(FlowSupport.config(context).getOrDefault(
                PixorexAppGateAuthenticatorFactory.CLIENT_ROLES, PixorexAppGateAuthenticatorFactory.DEFAULT_CLIENT_ROLES));
        String clientId = FlowSupport.clientId(context);
        RealmModel realm = context.getRealm();
        if (hasRole(realm, user, clientRoles.get(clientId))) {
            context.success();
            return;
        }
        context.getEvent().clone().user(user).detail("reason", "app_not_allowed").error(Errors.ACCESS_DENIED);
        context.challenge(FlowSupport.messagePage(context, "pixorexDeniedTitle", deniedMessage(realm, user, clientId, clientRoles)));
    }

    @Override
    public void action(AuthenticationFlowContext context) {
        authenticate(context);
    }

    static String deniedMessage(RealmModel realm, UserModel user, String clientId, Map<String, String> clientRoles) {
        if (WEB_CLIENT.equals(clientId) && hasRole(realm, user, clientRoles.get(MOBILE_CLIENT))) {
            return "pixorexUseMobileApp";
        }
        if (MOBILE_CLIENT.equals(clientId) && hasRole(realm, user, clientRoles.get(WEB_CLIENT))) {
            return "pixorexUseWebApp";
        }
        return "pixorexNoAccess";
    }

    static Map<String, String> parse(String pairs) {
        Map<String, String> map = new HashMap<>();
        if (pairs == null) {
            return map;
        }
        for (String pair : pairs.split(",")) {
            String[] parts = pair.split("=", 2);
            if (parts.length == 2 && !parts[0].isBlank() && !parts[1].isBlank()) {
                map.put(parts[0].trim(), parts[1].trim());
            }
        }
        return map;
    }

    private static boolean hasRole(RealmModel realm, UserModel user, String roleName) {
        if (roleName == null) {
            return false;
        }
        RoleModel role = realm.getRole(roleName);
        return role != null && user.hasRole(role);
    }

    @Override
    public boolean requiresUser() {
        return false;
    }

    @Override
    public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) {
        return true;
    }

    @Override
    public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) {
    }

    @Override
    public void close() {
    }
}
