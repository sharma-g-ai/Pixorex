package com.amzur.pixorex.keycloak.otp;

/**
 * Fixed-window limit on code sends (REQ-01.04), applied per user and per destination so two accounts sharing a
 * phone cannot double the allowance.
 */
public final class Throttle {

    public interface CounterStore {
        int get(String key);

        void increment(String key, long lifespanSeconds);
    }

    private final CounterStore store;
    private final int maxSends;
    private final int windowSeconds;

    public Throttle(CounterStore store, int maxSends, int windowSeconds) {
        this.store = store;
        this.maxSends = maxSends;
        this.windowSeconds = windowSeconds;
    }

    public static String userSubject(String userId) {
        return "u:" + userId;
    }

    public static String destinationSubject(String destination) {
        return "d:" + OtpCodes.sha256Hex(destination);
    }

    public boolean allowed(long nowSeconds, String... subjects) {
        for (String subject : subjects) {
            if (store.get(key(subject, nowSeconds)) >= maxSends) {
                return false;
            }
        }
        return true;
    }

    public void record(long nowSeconds, String... subjects) {
        long lifespan = secondsUntilReset(nowSeconds);
        for (String subject : subjects) {
            store.increment(key(subject, nowSeconds), lifespan);
        }
    }

    public long secondsUntilReset(long nowSeconds) {
        return windowSeconds - (nowSeconds % windowSeconds);
    }

    String key(String subject, long nowSeconds) {
        return "pxotp:" + subject + ":" + (nowSeconds / windowSeconds);
    }
}
