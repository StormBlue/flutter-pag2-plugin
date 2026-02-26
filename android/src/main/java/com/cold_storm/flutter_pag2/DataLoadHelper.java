package com.cold_storm.flutter_pag2;

import android.content.Context;
import android.os.Environment;
import android.util.Log;
import android.util.LruCache;

import androidx.core.content.pm.PackageInfoCompat;

import com.cold_storm.flutter_pag2.utils.EncodeUtil;
import com.jakewharton.disklrucache.DiskLruCache;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.List;

/**
 * 数据加载器。
 */
public final class DataLoadHelper {
    private static final String TAG = "DataLoadHelper";
    public static final long DEFAULT_DIS_SIZE = 30L * 1024L * 1024L;

    // 下载来源：flutter插件、其他
    public static final int FROM_PLUGIN = 0;
    public static final int FROM_OTHER = 1;

    private static DiskLruCache diskCache;
    private static final LruCache<String, byte[]> memoryCache =
            new LruCache<>((int) (Runtime.getRuntime().maxMemory() / 50L));
    private static final List<ILoadListener> loadListeners = new ArrayList<>();

    private DataLoadHelper() {}

    /**
     * PAG 二进制回调。
     */
    public interface PagDataCallback {
        void onResult(byte[] bytes);
    }

    /**
     * 加载 PAG 数据，默认来源 FROM_OTHER。
     */
    public static void loadPag(String src, PagDataCallback callback) {
        loadPag(src, callback, FROM_OTHER);
    }

    /**
     * 加载 PAG 数据。
     */
    public static void loadPag(final String src, final PagDataCallback callback, final int from) {
        final long startTime = System.currentTimeMillis();
        final String key = hashKeyForDisk(src);
        final byte[] bytes = memoryCache.get(key);
        List<ILoadListener> listeners = snapshotListeners();
        for (ILoadListener listener : listeners) {
            listener.loadStart(src, from);
        }

        if (bytes != null) {
            callback.onResult(bytes);
            long useTime = System.currentTimeMillis() - startTime;
            for (ILoadListener listener : listeners) {
                listener.loadComplete(src, bytes, useTime, "", from);
            }
            return;
        }

        new Thread(() -> loadPagByDisk(src, (byteArray, errorMsg) -> {
            callback.onResult(byteArray);
            long useTime = System.currentTimeMillis() - startTime;
            List<ILoadListener> callbackListeners = snapshotListeners();
            for (ILoadListener listener : callbackListeners) {
                listener.loadComplete(src, byteArray, useTime, errorMsg, from);
            }
        })).start();
    }

    /**
     * 初始化硬盘缓存。
     */
    public static void initDiskCache(Context context, long size) {
        if (diskCache != null) {
            Log.w(TAG, "diskCache do not need init again!");
            return;
        }

        File cacheDir = getDiskCacheDir(context, "pag");
        if (!cacheDir.exists()) {
            //noinspection ResultOfMethodCallIgnored
            cacheDir.mkdirs();
        }
        try {
            if (diskCache == null) {
                android.content.pm.PackageInfo packageInfo =
                        context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
                int versionCode = (int) PackageInfoCompat.getLongVersionCode(packageInfo);
                diskCache = DiskLruCache.open(cacheDir, versionCode, 1, size);
            }
        } catch (Exception e) {
            Log.e(TAG, "initDiskCache error: " + e);
        }
    }

    /**
     * 初始化硬盘缓存，使用默认大小。
     */
    public static void initDiskCache(Context context) {
        initDiskCache(context, DEFAULT_DIS_SIZE);
    }

    private static File getDiskCacheDir(Context context, String uniqueName) {
        String cachePath;
        if (Environment.MEDIA_MOUNTED.equals(Environment.getExternalStorageState())
                || !Environment.isExternalStorageRemovable()) {
            File externalCacheDir = context.getExternalCacheDir();
            cachePath = externalCacheDir != null ? externalCacheDir.getPath() : "";
        } else {
            cachePath = context.getCacheDir().getPath();
        }
        return new File(cachePath + File.separator + uniqueName);
    }

    private interface DiskLoadCallback {
        void onResult(byte[] bytes, String errorMsg);
    }

    // 硬盘或者网络获取
    private static synchronized void loadPagByDisk(String src, DiskLoadCallback callback) {
        String errorMsg = "";
        String key = hashKeyForDisk(src);
        DiskLruCache.Snapshot snapshot = null;
        byte[] bytes = null;
        try {
            if (diskCache != null) {
                snapshot = diskCache.get(key);
            }
            if (snapshot == null) {
                Log.d(TAG, "loadPag load from network");
                if (diskCache != null) {
                    DiskLruCache.Editor editor = diskCache.edit(key);
                    if (editor != null) {
                        boolean writeSuccess = false;
                        try (OutputStream outputStream = editor.newOutputStream(0)) {
                            writeSuccess = downloadUrlToStream(src, outputStream);
                        }
                        if (writeSuccess) {
                            editor.commit();
                        } else {
                            editor.abort();
                        }
                    }
                    diskCache.flush();
                    snapshot = diskCache.get(key);
                } else {
                    bytes = downloadUrlToBytes(src);
                }
            }
        } catch (IOException e) {
            Log.e(TAG, "loadPag load from network erro: " + e);
            errorMsg = "loadPag load from network error: " + e;
        }

        if (bytes == null && snapshot != null) {
            Log.d(TAG, "loadPag load from snapShot");
            try (InputStream inputStream = snapshot.getInputStream(0);
                 ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8 * 1024];
                int len;
                while ((len = inputStream.read(buffer)) != -1) {
                    outputStream.write(buffer, 0, len);
                }
                bytes = outputStream.toByteArray();
            } catch (IOException e) {
                Log.e(TAG, "loadPag load from snapShot erro: " + e);
                errorMsg = "loadPag load from network error: " + e;
            }
        }
        if (bytes == null && errorMsg.isEmpty()) {
            errorMsg = "loadPag load from network error: empty data";
        }

        Log.d(TAG, "loadPag bytes size: " + (bytes == null ? null : bytes.length));
        if (bytes != null && bytes.length > 0 && memoryCache.get(key) == null) {
            memoryCache.put(key, bytes);
        }
        callback.onResult(bytes, errorMsg);
    }

    private static byte[] downloadUrlToBytes(String urlString) {
        try (ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {
            if (downloadUrlToStream(urlString, outputStream)) {
                return outputStream.toByteArray();
            }
        } catch (IOException e) {
            Log.e(TAG, "downloadUrlToBytes error: " + e);
        }
        return null;
    }

    private static boolean downloadUrlToStream(String urlString, OutputStream outputStream) {
        HttpURLConnection urlConnection = null;
        BufferedOutputStream outStream = null;
        BufferedInputStream inStream = null;
        try {
            URL url = new URL(urlString);
            urlConnection = (HttpURLConnection) url.openConnection();
            inStream = new BufferedInputStream(urlConnection.getInputStream(), 8 * 1024);
            outStream = new BufferedOutputStream(outputStream, 8 * 1024);
            byte[] buf = new byte[8 * 1024];
            int len;
            while ((len = inStream.read(buf)) != -1) {
                outStream.write(buf, 0, len);
            }
            return true;
        } catch (IOException e) {
            Log.e(TAG, "downloadUrlToStream error: " + e);
        } finally {
            if (urlConnection != null) {
                urlConnection.disconnect();
            }
            try {
                if (outStream != null) {
                    outStream.close();
                }
                if (inStream != null) {
                    inStream.close();
                }
            } catch (IOException e) {
                Log.e(TAG, "close stream error: " + e);
            }
        }
        return false;
    }

    // 使用MD5算法对传入的key进行加密并返回
    private static String hashKeyForDisk(String key) {
        try {
            MessageDigest digest = MessageDigest.getInstance("MD5");
            digest.update(key.getBytes());
            String md5 = EncodeUtil.bytesToHexString(digest.digest());
            if (md5 != null) {
                return md5;
            }
        } catch (NoSuchAlgorithmException ignored) {
            // fallback below
        }
        return String.valueOf(key.hashCode());
    }

    public static void addLoadListener(ILoadListener loadListener) {
        synchronized (loadListeners) {
            loadListeners.add(loadListener);
        }
    }

    public static void removeLoadListener(ILoadListener loadListener) {
        synchronized (loadListeners) {
            loadListeners.remove(loadListener);
        }
    }

    private static List<ILoadListener> snapshotListeners() {
        synchronized (loadListeners) {
            return new ArrayList<>(loadListeners);
        }
    }
}
