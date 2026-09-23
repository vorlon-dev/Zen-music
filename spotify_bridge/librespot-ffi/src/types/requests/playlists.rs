use serde::Serialize;

#[derive(Serialize)]
pub struct AddItemRequest {
    pub uris: Vec<String>,
    pub position: Option<u32>,
}

#[derive(Serialize)]
pub struct RemoveItemRequest {
    pub items: Vec<RemoveItem>,
}

#[derive(Serialize)]
pub struct RemoveItem {
    pub uri: String,
}

#[derive(Serialize)]
pub struct CreatePlaylistRequest {
    pub name: String,
    pub public: bool,
    // Public has to be set to false for collaborative to work
    pub collaborative: bool,
    pub description: Option<String>,
}
