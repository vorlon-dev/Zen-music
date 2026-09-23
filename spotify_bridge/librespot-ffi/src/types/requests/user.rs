use serde::Serialize;

#[derive(Serialize)]
pub struct UserTopRequest {
    pub r#type: String,
}
