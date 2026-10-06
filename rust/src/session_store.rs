use std::{
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use keyring::Entry;
use matrix_sdk::{
    authentication::{
        matrix::MatrixSession,
        oauth::{ClientId, OAuthSession, UserSession},
    },
    AuthSession,
};
use serde::{Deserialize, Serialize};

const KEYRING_SERVICE: &str = "com.danielmessias.matrix_messenger";

const STORE_DIR_NAME: &str = "matrix_store";

#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct StoredSession {
    pub homeserver_url: String,
    pub store_name: String,
    pub passphrase: String,
    pub auth: SavedAuth,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub(crate) enum SavedAuth {
    Password(MatrixSession),
    OAuth {
        client_id: String,
        user: UserSession,
    },
}

impl SavedAuth {
    pub(crate) fn from_session(session: AuthSession) -> Option<Self> {
        match session {
            AuthSession::Matrix(session) => Some(Self::Password(session)),
            AuthSession::OAuth(session) => {
                let OAuthSession { client_id, user } = *session;
                Some(Self::OAuth {
                    client_id: client_id.into(),
                    user,
                })
            }
            _ => None,
        }
    }

    pub(crate) fn into_session(self) -> AuthSession {
        match self {
            Self::Password(session) => session.into(),
            Self::OAuth { client_id, user } => OAuthSession {
                client_id: ClientId::new(client_id),
                user,
            }
            .into(),
        }
    }
}

pub(crate) fn load(data_dir: &str) -> Result<Option<StoredSession>, String> {
    parse_loaded(Entry::new(KEYRING_SERVICE, data_dir).and_then(|entry| entry.get_password()))
}

fn parse_loaded(read: keyring::Result<String>) -> Result<Option<StoredSession>, String> {
    match read {
        Ok(json) => serde_json::from_str(&json)
            .map(Some)
            .map_err(|e| format!("sessão salva ilegível: {e}")),
        Err(keyring::Error::NoEntry) => Ok(None),
        // Sem cofre o login não salva a sessão, então não há o que restaurar.
        Err(keyring::Error::NoDefaultStore) => {
            log::warn!("cofre do sistema indisponível, sessão não restaurada");
            Ok(None)
        }
        Err(e) => Err(format!("falha ao ler o cofre do sistema: {e}")),
    }
}

pub(crate) fn save(data_dir: &str, stored: &StoredSession) -> Result<(), String> {
    let json = serde_json::to_string(stored).map_err(|e| e.to_string())?;
    keyring_entry(data_dir)?
        .set_password(&json)
        .map_err(|e| format!("falha ao gravar no cofre do sistema: {e}"))
}

pub(crate) fn delete(data_dir: &str) -> Result<(), String> {
    match keyring_entry(data_dir)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(format!("falha ao apagar do cofre do sistema: {e}")),
    }
}

/// Uma entrada por `data_dir`, para os testes não compartilharem a sessão do app.
fn keyring_entry(data_dir: &str) -> Result<Entry, String> {
    Entry::new(KEYRING_SERVICE, data_dir).map_err(|e| format!("cofre do sistema indisponível: {e}"))
}

pub(crate) fn stores_dir(data_dir: &str) -> PathBuf {
    PathBuf::from(data_dir).join(STORE_DIR_NAME)
}

pub(crate) fn unique_store_name() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("login_{nanos}")
}

pub(crate) fn new_passphrase() -> Result<String, String> {
    let mut bytes = [0u8; 32];
    getrandom::getrandom(&mut bytes).map_err(|e| format!("falha ao gerar passphrase: {e}"))?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

/// Stores ainda abertos não podem ser apagados no Windows; ficam para a próxima limpeza.
pub(crate) fn remove_stores_except(stores_dir: &Path, keep: Option<&str>) {
    let Ok(entries) = std::fs::read_dir(stores_dir) else {
        return;
    };
    for entry in entries.flatten() {
        if keep.is_some_and(|keep| entry.file_name() == keep) {
            continue;
        }
        let path = entry.path();
        let _ = if path.is_dir() {
            std::fs::remove_dir_all(&path)
        } else {
            std::fs::remove_file(&path)
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remove_stores_except_keeps_only_the_given_store() {
        let stores_dir = std::env::temp_dir()
            .join("matrix_messenger_tests")
            .join("remove_stores")
            .join(STORE_DIR_NAME);
        std::fs::create_dir_all(stores_dir.join("login_1")).unwrap();
        std::fs::create_dir_all(stores_dir.join("login_2")).unwrap();
        std::fs::write(stores_dir.join("matrix-sdk-state.sqlite3"), b"").unwrap();

        remove_stores_except(&stores_dir, Some("login_2"));

        let remaining: Vec<_> = std::fs::read_dir(&stores_dir)
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(remaining, ["login_2"]);
    }

    #[test]
    fn remove_stores_except_ignores_missing_dir() {
        remove_stores_except(Path::new("/caminho/que/nao/existe"), None);
    }

    #[test]
    fn passphrase_is_random_hex() {
        let a = new_passphrase().unwrap();
        let b = new_passphrase().unwrap();
        assert_eq!(a.len(), 64);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a, b);
    }

    use crate::test_support::{session_meta, tokens};

    #[test]
    fn password_auth_round_trips_through_json() {
        let auth = SavedAuth::Password(MatrixSession {
            meta: session_meta(),
            tokens: tokens("refresh"),
        });

        let json = serde_json::to_string(&auth).unwrap();
        let SavedAuth::Password(session) = serde_json::from_str(&json).unwrap() else {
            panic!("variante errada: {json}");
        };

        assert_eq!(session.meta.device_id, "DEVICE");
        assert_eq!(session.tokens.access_token, "access-refresh");
    }

    #[test]
    fn oauth_auth_round_trips_through_json() {
        let auth = SavedAuth::OAuth {
            client_id: "client".into(),
            user: UserSession {
                meta: session_meta(),
                tokens: tokens("refresh"),
            },
        };

        let json = serde_json::to_string(&auth).unwrap();
        let SavedAuth::OAuth { client_id, user } = serde_json::from_str(&json).unwrap() else {
            panic!("variante errada: {json}");
        };

        assert_eq!(client_id, "client");
        assert_eq!(user.tokens.refresh_token.as_deref(), Some("refresh"));
    }

    #[test]
    fn oauth_session_converts_both_ways() {
        let session = AuthSession::OAuth(Box::new(OAuthSession {
            client_id: ClientId::new("client".into()),
            user: UserSession {
                meta: session_meta(),
                tokens: tokens("refresh"),
            },
        }));

        let saved = SavedAuth::from_session(session).expect("sessão OAuth suportada");
        let AuthSession::OAuth(restored) = saved.into_session() else {
            panic!("deveria voltar como OAuth");
        };

        assert_eq!(*restored.client_id, "client");
        assert_eq!(restored.user.meta.user_id, "@alice:example.org");
    }

    #[test]
    fn missing_vault_loads_no_session() {
        assert!(matches!(
            parse_loaded(Err(keyring::Error::NoDefaultStore)),
            Ok(None)
        ));
    }

    #[test]
    fn locked_vault_is_an_error() {
        let locked = keyring::Error::NoStorageAccess("bloqueado".into());
        assert!(parse_loaded(Err(locked)).is_err());
    }
}
