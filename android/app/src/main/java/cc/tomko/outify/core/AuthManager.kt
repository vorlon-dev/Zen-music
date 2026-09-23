package cc.tomko.outify.core

class AuthManager {
    external fun hasCachedCredentials(): Boolean
    external fun getAuthorizationURL(): String?
    external fun handleOAuthCode(code: String, state: String): String

    companion object {
        @JvmStatic
        external fun logout(): Boolean
    }
}