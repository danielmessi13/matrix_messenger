// Os futures da Timeline do matrix-sdk-ui passam do limite padrão de 128 na checagem de tipos.
#![recursion_limit = "256"]
pub mod api;
mod client_builder;
mod diff_window;
mod frb_generated;
mod media;
mod notifications;
mod oidc_callback;
mod recent_threads;
mod room_list;
mod session_store;
#[cfg(test)]
mod test_support;
mod threads;
mod timeline;
mod typing;
