use librespot_core::SpotifyUri;

use crate::session::get_username;

#[derive(Clone, PartialEq, Eq, Hash)]
pub enum OutifyUri {
    Spotify(SpotifyUri),
    Liked,
    ArtistLiked { id: String },
}

impl OutifyUri {
    pub fn from_uri(uri: &str) -> Self {
        let mut parts = uri.split(':');

        match parts.next() {
            Some("spotify") => match SpotifyUri::from_uri(uri) {
                Ok(spotify_uri) => Self::Spotify(spotify_uri),
                Err(_) => Self::Spotify(SpotifyUri::Unknown {
                    kind: parts.next().unwrap_or("").to_owned().into(),
                    id: parts.next().unwrap_or("").to_owned(),
                }),
            },

            Some("outify") => match (parts.next(), parts.next(), parts.next()) {
                (Some("liked"), Some("artist"), Some(id)) => {
                    Self::ArtistLiked { id: id.to_owned() }
                }
                (Some("liked"), _, _) => Self::Liked,
                (Some(kind), Some(id), _) => Self::Spotify(SpotifyUri::Unknown {
                    kind: kind.to_owned().into(),
                    id: id.to_owned(),
                }),
                _ => Self::Spotify(SpotifyUri::Unknown {
                    kind: "".to_owned().into(),
                    id: "".to_owned(),
                }),
            },

            Some(kind) => Self::Spotify(SpotifyUri::Unknown {
                kind: kind.to_owned().into(),
                id: parts.next().unwrap_or("").to_owned(),
            }),

            None => Self::Spotify(SpotifyUri::Unknown {
                kind: "".to_owned().into(),
                id: "".to_owned(),
            }),
        }
    }

    pub fn to_uri(&self) -> String {
        let user_id = get_username();
        match &self {
            OutifyUri::Spotify(uri) => uri.to_uri(),
            OutifyUri::Liked => {
                format!("spotify:user:{}:collection", user_id)
            }
            OutifyUri::ArtistLiked { id } => {
                format!("spotify:user:{}:collection:artist:{}", user_id, id)
            }
        }
    }
}
