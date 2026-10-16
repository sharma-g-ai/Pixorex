package com.amzur.pixorex.keycloak.otp;

import java.util.Map;

import org.keycloak.models.SingleUseObjectProvider;

/** Throttle counters in Keycloak's single-use-object store, which is cluster-wide and expires entries on its own. */
public final class SingleUseCounterStore implements Throttle.CounterStore {

    private static final String COUNT = "n";

    private final SingleUseObjectProvider store;

    public SingleUseCounterStore(SingleUseObjectProvider store) {
        this.store = store;
    }

    @Override
    public int get(String key) {
        Map<String, String> entry = store.get(key);
        if (entry == null || entry.get(COUNT) == null) {
            return 0;
        }
        try {
            return Integer.parseInt(entry.get(COUNT));
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    @Override
    public void increment(String key, long lifespanSeconds) {
        int next = get(key) + 1;
        if (next == 1 || !store.replace(key, Map.of(COUNT, String.valueOf(next)))) {
            store.put(key, Math.max(1, lifespanSeconds), Map.of(COUNT, String.valueOf(next)));
        }
    }
}
