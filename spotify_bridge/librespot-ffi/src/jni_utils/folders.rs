use std::path::PathBuf;

use jni::{
    JNIEnv,
    objects::{JObject, JString},
};

pub(crate) fn get_android_dir(env: &mut JNIEnv, context: &JObject, method: &str) -> PathBuf {
    // Call context.getFilesDir() or context.getCacheDir()
    let dir_object: JObject = env
        .call_method(context, method, "()Ljava/io/File;", &[])
        .expect("Failed to call method")
        .l()
        .expect("Method returned null");

    // Call getAbsolutePath() on File object
    let path_jstring: JString = env
        .call_method(dir_object, "getAbsolutePath", "()Ljava/lang/String;", &[])
        .expect("Failed to get absolute path")
        .l()
        .expect("Path is null")
        .into();

    let path: String = env
        .get_string(&path_jstring)
        .expect("Invalid string")
        .into();
    PathBuf::from(path)
}
