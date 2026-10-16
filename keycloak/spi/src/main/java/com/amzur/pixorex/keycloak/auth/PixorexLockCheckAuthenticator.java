package com.amzur.pixorex.keycloak.auth;

import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.Authenticator;
import org.keycloak.events.Errors;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;

public class PixorexLockCheckAuthenticator implements Authenticator {

    @Override
    public void authenticate(AuthenticationFlowContext context) {
        UserModel user = context.getUser();
        if (user == null || !isLocked(context, user)) {
            context.success();
            return;
        }
        context.getEvent().clone().user(user).error(Errors.USER_TEMPORARILY_DISABLED);
        context.challenge(FlowSupport.lockedPage(context, FlowSupport.lockMinutesLeft(context, user)));
    }

    @Override
    public void action(AuthenticationFlowContext context) {
        authenticate(context);
    }

    static boolean isLocked(AuthenticationFlowContext context, UserModel user) {
        return context.getRealm().isBruteForceProtected()
                && context.getProtector().isTemporarilyDisabled(context.getSession(), context.getRealm(), user);
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
