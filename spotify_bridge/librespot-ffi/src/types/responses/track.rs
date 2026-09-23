use super::{
    album::AlbumObject,
    artist::{ArtistObject, SimplifiedArtistObject},
    common::*,
    pagination::Page,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackObject {
    pub album: Option<AlbumObject>,
    pub artists: Option<Vec<SimplifiedArtistObject>>,
    pub available_markets: Option<Vec<String>>,
    pub disc_number: Option<i32>,
    pub duration_ms: Option<i32>,
    pub explicit: Option<bool>,
    pub external_ids: Option<ExternalIds>,
    pub external_urls: Option<ExternalUrls>,
    pub href: Option<String>,
    pub id: Option<String>,
    pub is_playable: Option<bool>,
    pub linked_from: Option<LinkedFromObject>,
    pub restrictions: Option<RestrictionsObject>,
    pub name: String,
    pub popularity: Option<i32>,
    pub preview_url: Option<String>,
    pub track_number: Option<i32>,
    #[serde(rename = "type")]
    pub object_type: String,
    pub uri: Option<String>,
    pub is_local: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LinkedFromObject {
    pub external_urls: Option<ExternalUrls>,
    pub href: Option<String>,
    pub id: Option<String>,
    pub uri: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ArtistOrTrack {
    Artist(ArtistObject),
    Track(TrackObject),
}

pub type ArtistsOrTracksPage = Page<ArtistOrTrack>;
