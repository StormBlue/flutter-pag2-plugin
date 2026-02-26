package com.cold_storm.flutter_pag2;

/**
 * 用于监听 PAG 加载情况。
 */
public interface ILoadListener {

    void loadStart(String url, int from);

    void loadComplete(String url, byte[] result, long useTime, String errorMsg, int from);
}
