use serde::Serialize;

#[derive(Serialize)]
pub struct TransferPlaybackRequest {
    pub device_ids: Vec<String>,
}
