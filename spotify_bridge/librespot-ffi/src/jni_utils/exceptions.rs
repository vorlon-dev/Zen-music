#[macro_export]
macro_rules! make_global_exception {
    (
        $env:expr,
        $class:literal,
        $ctor_sig:literal,
        [$($arg:expr),* $(,)?]
    ) => {{
        // Convert each $arg into a JObject before converting to JValue.
        // This expects the $arg to be a JString, JObject, or other JNI object.
        let ex = $env
            .new_object(
                $class,
                $ctor_sig,
                &[
                    $(
                        ::jni::objects::JValue::from(::jni::objects::JObject::from($arg))
                    ),*
                ],
            )
            .expect("failed to create Java exception");

        $env
            .new_global_ref(ex)
            .expect("failed to create GlobalRef for exception")
    }};
}
