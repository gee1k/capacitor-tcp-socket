package com.svend.plugins.tcp.socket;

import android.util.Log;

public class TcpSocket {

    public String echo(String value) {
        Log.i("Echo", value);
        return value;
    }
}
