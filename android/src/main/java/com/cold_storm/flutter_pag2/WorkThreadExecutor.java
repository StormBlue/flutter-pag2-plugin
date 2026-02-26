package com.cold_storm.flutter_pag2;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;


public class WorkThreadExecutor {
    private static volatile WorkThreadExecutor instance;
    private final ExecutorService executor;
    public static boolean multiThread = true;

    private WorkThreadExecutor() {
        executor = Executors.newCachedThreadPool();
    }

    public static WorkThreadExecutor getInstance() {
        if (instance == null) {
            synchronized (WorkThreadExecutor.class) {
                if (instance == null) {
                    instance = new WorkThreadExecutor();
                }
            }
        }
        return instance;
    }

    public void enableMultiThread(boolean enabled) {
        multiThread = enabled;
    }

    public void post(Runnable task) {
        if (multiThread) {
            executor.execute(task);
        } else {
            task.run();
        }
    }

}
