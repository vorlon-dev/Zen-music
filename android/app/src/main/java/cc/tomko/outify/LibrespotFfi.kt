package cc.tomko.outify

import android.content.Context

object LibrespotFfi {

    @JvmStatic
    external fun libInit(
        context: Context,
        clientId: String,
        clientSecret: String
    )

    @JvmStatic
    external fun updateClientCredentials(clientId: String, clientSecret: String)
}