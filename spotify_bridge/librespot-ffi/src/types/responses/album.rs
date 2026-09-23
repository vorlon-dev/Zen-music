use super::{artist::SimplifiedArtistObject, common::*};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlbumObject {
    pub href: Option<String>,
    pub id: Option<String>,
    pub name: Option<String>,
    pub album_type: Option<String>,
    pub album_group: Option<String>,
    pub artists: Option<Vec<SimplifiedArtistObject>>,
    pub images: Option<Vec<ImageObject>>,
    pub uri: Option<String>,
}
