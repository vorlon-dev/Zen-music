use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct UserJson {
    pub uri: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub image_url: String,
    #[serde(default)]
    pub followers_count: i32,
    #[serde(default)]
    pub following_count: i32,
    #[serde(default)]
    pub is_following: bool,
    pub color: i32,
    #[serde(default)]
    pub allow_follows: bool,
    #[serde(default)]
    pub show_follows: bool,

    #[serde(default)]
    pub total_public_playlists_count: i32,
    #[serde(default)]
    pub public_playlists: Vec<UserPublicPlaylistJson>,
}

#[derive(Serialize, Deserialize)]
pub struct UserPublicPlaylistJson {
    pub uri: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub image_url: String,
    #[serde(default)]
    pub followers_count: i32,
    pub owner_uri: String,
    #[serde(default)]
    pub is_following: bool,
}
