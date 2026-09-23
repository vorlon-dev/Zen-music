use serde::Deserialize;

#[derive(Deserialize)]
pub struct CreatePlaylistResponse {
    pub id: String,
}
