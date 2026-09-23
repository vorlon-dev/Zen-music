use librespot_metadata::playlist::{
    attribute::{PlaylistAttributes, PlaylistItemAttributes},
    diff::PlaylistDiff,
    item::PlaylistItem,
    operation::PlaylistOperation,
};
use librespot_metadata::{Playlist, playlist::operation::PlaylistOperationKind};
use serde::Serialize;

use serde_json::Value as JsonValue;
use std::collections::HashMap;

// Serializable Playlist object
#[derive(Serialize)]
pub struct PlaylistJson {
    id: String,
    uri: String,
    owner_username: String,
    revision: String,
    length: i32,
    attributes: PlaylistAttributesJson,
    contents: Vec<PlaylistItemJson>,
    timestamp: i64,
    diff: Option<PlaylistDiffJson>,
}

// Serializable PlaylistAttributes object
#[derive(Serialize)]
pub struct PlaylistAttributesJson {
    name: String,
    description: String,
    picture: Vec<u8>,
    is_collaborative: bool,
    pl3_version: String,
    is_deleted_by_owner: bool,
    client_id: String,
    format: String,
    /// Map of format attribute key -> value (matches `PlaylistFormatAttribute` which is
    /// a `HashMap<String,String>` in your model).
    format_attributes: HashMap<String, String>,
    /// hex id of the picture (kept for compatibility with your previous shape)
    picture_id: String,
}

// Serializable PlaylistItem
#[derive(Serialize)]
pub struct PlaylistItemJson {
    id: String,
    uri: String,
    attributes: PlaylistItemAttributesJson,
}

#[derive(Serialize)]
pub struct PlaylistItemAttributesJson {
    added_by: String,
    timestamp: i64,
    seen_at: i64,
    is_public: bool,
    /// Map of format attribute key -> value
    format_attributes: HashMap<String, String>,
    item_id: Vec<u8>,
}

#[derive(Serialize)]
pub struct PlaylistDiffJson {
    #[serde(rename = "from_revision")]
    pub from_revision: String,
    #[serde(rename = "to_revision")]
    pub to_revision: String,
    pub operations: Vec<PlaylistOperationJson>,
}

#[derive(Serialize)]
pub struct PlaylistOperationJson {
    pub kind: String, // "add" / "rem" / "mov" / "update_item_attributes" / "update_list_attributes"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub add: Option<PlaylistOperationAddJson>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rem: Option<PlaylistOperationRemoveJson>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mov: Option<PlaylistOperationMoveJson>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub update_item_attributes: Option<PlaylistUpdateItemAttributesJson>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub update_list_attributes: Option<PlaylistUpdateListAttributesJson>,
}

#[derive(Serialize)]
pub struct PlaylistOperationAddJson {
    pub from_index: i32,
    pub items: Vec<PlaylistItemJson>,
    pub add_last: bool,
    pub add_first: bool,
}

#[derive(Serialize)]
pub struct PlaylistOperationMoveJson {
    pub from_index: i32,
    pub length: i32,
    pub to_index: i32,
}

#[derive(Serialize)]
pub struct PlaylistOperationRemoveJson {
    pub from_index: i32,
    pub length: i32,
    pub items: Vec<PlaylistItemJson>,
    pub has_items_as_key: bool,
}

#[derive(Serialize)]
pub struct PlaylistUpdateItemAttributesJson {
    // minimal set; extend as needed
    pub position: Option<i32>,
    pub length: Option<i32>,
    pub items: Vec<PlaylistItemJson>,
    pub added_by: Option<String>,
    pub timestamp: Option<i64>,
    #[serde(rename = "seen_at")]
    pub seen_at: Option<i64>,
    #[serde(rename = "is_public")]
    pub is_public: Option<bool>,

    /// format attributes present on the item update (optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub format_attributes: Option<HashMap<String, String>>,
}

#[derive(Serialize)]
pub struct PlaylistUpdateListAttributesJson {
    pub name: Option<String>,
    pub description: Option<String>,
    #[serde(rename = "is_deleted_by_owner")]
    pub is_deleted_by_owner: Option<bool>,

    /// optional format attributes carried in list attribute updates
    #[serde(skip_serializing_if = "Option::is_none")]
    pub format_attributes: Option<HashMap<String, String>>,

    /// optional picture sizes carried in list attribute updates
    #[serde(skip_serializing_if = "Option::is_none")]
    pub picture_sizes: Option<JsonValue>,
}

impl From<&PlaylistItemAttributes> for PlaylistItemAttributesJson {
    fn from(attr: &PlaylistItemAttributes) -> Self {
        Self {
            added_by: attr.added_by.clone(),
            timestamp: attr.timestamp.unix_timestamp(),
            seen_at: attr.seen_at.unix_timestamp(),
            is_public: attr.is_public,
            format_attributes: attr.format_attributes.0.clone(),
            item_id: attr.item_id.clone(),
        }
    }
}

impl From<&Playlist> for PlaylistJson {
    fn from(playlist: &Playlist) -> Self {
        Self {
            id: playlist.id.to_id(),
            uri: playlist.id.to_uri(),
            owner_username: playlist.owner_username.clone(),
            revision: playlist
                .revision
                .clone()
                .iter()
                .map(|b| format!("{:02x}", b))
                .collect::<String>(),
            length: playlist.length,
            attributes: PlaylistAttributesJson::from(&playlist.attributes),
            contents: playlist
                .contents
                .items
                .iter()
                .map(|item| PlaylistItemJson::from(item)) // pass each item (which is &PlaylistItem)
                .collect(),
            timestamp: playlist.timestamp.unix_timestamp(),
            diff: playlist.diff.as_ref().map(|d| PlaylistDiffJson::from(d)),
        }
    }
}

impl From<&PlaylistAttributes> for PlaylistAttributesJson {
    fn from(attr: &PlaylistAttributes) -> Self {
        // picture_id as hex remains for backward compatibility
        let picture_id = attr
            .picture
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>();

        Self {
            name: attr.name.clone(),
            description: attr.description.clone(),
            picture: attr.picture.clone(),
            is_collaborative: attr.is_collaborative,
            pl3_version: attr.pl3_version.clone(),
            is_deleted_by_owner: attr.is_deleted_by_owner,
            client_id: attr.client_id.clone(),
            format: attr.format.clone(),
            format_attributes: attr.format_attributes.0.clone(),
            picture_id,
        }
    }
}

impl From<&PlaylistItem> for PlaylistItemJson {
    fn from(item: &PlaylistItem) -> Self {
        Self {
            id: item.id.to_id(),
            uri: item.id.to_uri(),
            attributes: PlaylistItemAttributesJson::from(&item.attributes),
        }
    }
}

impl From<&PlaylistDiff> for PlaylistDiffJson {
    fn from(d: &PlaylistDiff) -> Self {
        Self {
            from_revision: d.from_revision.to_base62(),
            to_revision: d.to_revision.to_base62(),
            operations: d
                .operations
                .iter()
                .map(|op| PlaylistOperationJson::from(op))
                .collect(),
        }
    }
}

impl From<&PlaylistOperation> for PlaylistOperationJson {
    fn from(op: &PlaylistOperation) -> Self {
        let kind = match op.kind {
            PlaylistOperationKind::ADD => "add",
            PlaylistOperationKind::REM => "rem",
            PlaylistOperationKind::MOV => "mov",
            PlaylistOperationKind::UPDATE_ITEM_ATTRIBUTES => "update_item_attributes",
            PlaylistOperationKind::UPDATE_LIST_ATTRIBUTES => "update_list_attributes",
            _ => "unknown",
        }
        .to_string();

        let add = if op.kind == PlaylistOperationKind::ADD {
            Some(PlaylistOperationAddJson {
                from_index: op.add.from_index,
                items: op.add.items.iter().map(PlaylistItemJson::from).collect(),
                add_last: op.add.add_last,
                add_first: op.add.add_first,
            })
        } else {
            None
        };

        let rem = if op.kind == PlaylistOperationKind::REM {
            Some(PlaylistOperationRemoveJson {
                from_index: op.rem.from_index,
                length: op.rem.length,
                items: op.rem.items.iter().map(PlaylistItemJson::from).collect(),
                has_items_as_key: op.rem.has_items_as_key,
            })
        } else {
            None
        };

        let mov = if op.kind == PlaylistOperationKind::MOV {
            Some(PlaylistOperationMoveJson {
                from_index: op.mov.from_index,
                length: op.mov.length,
                to_index: op.mov.to_index,
            })
        } else {
            None
        };

        // Minimal, safe item-update representation — only the index is public.
        let update_item_attributes = if op.kind == PlaylistOperationKind::UPDATE_ITEM_ATTRIBUTES {
            Some(PlaylistUpdateItemAttributesJson {
                position: Some(op.update_item_attributes.index),
                length: None,
                items: Vec::new(),
                added_by: None,
                timestamp: None,
                seen_at: None,
                is_public: None,
                format_attributes: None,
            })
        } else {
            None
        };

        // Minimal, safe list-update representation (internals private → leave fields None)
        let update_list_attributes = if op.kind == PlaylistOperationKind::UPDATE_LIST_ATTRIBUTES {
            Some(PlaylistUpdateListAttributesJson {
                name: None,
                description: None,
                is_deleted_by_owner: None,
                format_attributes: None,
                picture_sizes: None,
            })
        } else {
            None
        };

        PlaylistOperationJson {
            kind,
            add,
            rem,
            mov,
            update_item_attributes,
            update_list_attributes,
        }
    }
}
