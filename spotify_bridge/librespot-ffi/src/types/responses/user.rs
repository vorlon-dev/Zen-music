use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct CurrentUserResponse {
    pub country: Option<String>,
    pub display_name: Option<String>,
    pub email: Option<String>,
    pub explicit_content: ExplicitContent,
    pub external_urls: ExternalUrls,
    pub followers: Followers,
    pub href: Option<String>,
    pub id: Option<String>,
    pub images: Vec<Image>,
    pub product: Option<String>,
    #[serde(rename = "type")]
    pub user_type: String,
    pub uri: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ExplicitContent {
    pub filter_enabled: bool,
    pub filter_locked: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ExternalUrls {
    pub spotify: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Followers {
    pub href: Option<String>,
    pub total: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Image {
    pub url: String,
    pub height: u32,
    pub width: u32,
}
