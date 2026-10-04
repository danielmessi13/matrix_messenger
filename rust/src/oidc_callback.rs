use std::{net::Ipv4Addr, time::Duration};

use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    net::{TcpListener, TcpStream},
    sync::mpsc,
};
use url::Url;

const CALLBACK_PATH: &str = "/callback";

// Navegadores abrem conexões extras (preconnect) que podem ficar paradas.
const CONNECTION_TIMEOUT: Duration = Duration::from_secs(30);

const MAX_REQUEST_HEAD: u64 = 16 * 1024;

pub(crate) struct CallbackServer {
    listener: TcpListener,
    redirect_uri: Url,
}

#[derive(Debug)]
pub(crate) enum CallbackError {
    TimedOut,
    Io(std::io::Error),
}

impl From<std::io::Error> for CallbackError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}

impl CallbackServer {
    pub(crate) async fn bind() -> std::io::Result<Self> {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
        let port = listener.local_addr()?.port();
        let redirect_uri = Url::parse(&format!("http://127.0.0.1:{port}{CALLBACK_PATH}"))
            .expect("URL de loopback válida");
        Ok(Self {
            listener,
            redirect_uri,
        })
    }

    pub(crate) fn redirect_uri(&self) -> &Url {
        &self.redirect_uri
    }

    pub(crate) async fn wait_for_query(
        &self,
        expected_state: &str,
        timeout: Duration,
    ) -> Result<String, CallbackError> {
        tokio::time::timeout(timeout, self.accept_callback(expected_state))
            .await
            .map_err(|_| CallbackError::TimedOut)?
    }

    async fn accept_callback(&self, expected_state: &str) -> Result<String, CallbackError> {
        let (queries, mut received) = mpsc::channel(1);
        loop {
            tokio::select! {
                accepted = self.listener.accept() => {
                    let (stream, _) = accepted?;
                    tokio::spawn(handle_connection(
                        stream,
                        expected_state.to_owned(),
                        queries.clone(),
                    ));
                }
                Some(query) = received.recv() => return Ok(query),
            }
        }
    }
}

async fn handle_connection(
    mut stream: TcpStream,
    expected_state: String,
    queries: mpsc::Sender<String>,
) {
    let Ok(Some(request_line)) =
        tokio::time::timeout(CONNECTION_TIMEOUT, read_request_head(&mut stream))
            .await
            .unwrap_or(Ok(None))
    else {
        return;
    };

    match parse_callback(&request_line) {
        // Uma aba antiga ou outro processo local não pode encerrar o login em andamento.
        Some(query) if query_state(&query).as_deref() != Some(expected_state.as_str()) => {
            respond(&mut stream, "400 Bad Request", String::new()).await;
        }
        Some(query) => {
            respond(&mut stream, "200 OK", result_page(&query)).await;
            queries.send(query).await.ok();
        }
        None => respond(&mut stream, "404 Not Found", String::new()).await,
    }
}

// Lê o cabeçalho inteiro: fechar a conexão com dados não lidos faz o navegador mostrar erro de conexão.
async fn read_request_head(stream: &mut TcpStream) -> std::io::Result<Option<String>> {
    let mut reader = BufReader::new(stream.take(MAX_REQUEST_HEAD));
    let mut request_line = String::new();
    if reader.read_line(&mut request_line).await? == 0 {
        return Ok(None);
    }
    let mut header = String::new();
    while reader.read_line(&mut header).await? > 0 && header != "\r\n" && header != "\n" {
        header.clear();
    }
    Ok(Some(request_line.trim_end().to_owned()))
}

pub(crate) fn parse_callback(request_line: &str) -> Option<String> {
    let mut parts = request_line.split_whitespace();
    if parts.next()? != "GET" {
        return None;
    }
    let target = parts.next()?;
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    (path == CALLBACK_PATH).then(|| query.to_owned())
}

fn query_state(query: &str) -> Option<String> {
    url::form_urlencoded::parse(query.as_bytes())
        .find(|(key, _)| key == "state")
        .map(|(_, value)| value.into_owned())
}

fn result_page(query: &str) -> String {
    let message = if query.split('&').any(|pair| pair.starts_with("code=")) {
        "Você já pode fechar esta aba e voltar ao Matrix Messenger."
    } else {
        "O login não foi concluído. Volte ao Matrix Messenger."
    };
    format!(
        "<!doctype html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\">\
         <title>Matrix Messenger</title></head>\
         <body style=\"font-family: sans-serif; text-align: center; margin-top: 20vh\">\
         <p>{message}</p></body></html>"
    )
}

async fn respond(stream: &mut TcpStream, status: &str, body: String) {
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\n\
         Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    stream.write_all(response.as_bytes()).await.ok();
    stream.shutdown().await.ok();
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpStream,
    };

    async fn send(server: &CallbackServer, request: &str) -> String {
        let port = server.redirect_uri().port().unwrap();
        let mut stream = TcpStream::connect((Ipv4Addr::LOCALHOST, port))
            .await
            .unwrap();
        stream.write_all(request.as_bytes()).await.unwrap();
        let mut response = String::new();
        stream.read_to_string(&mut response).await.unwrap();
        response
    }

    #[test]
    fn parses_callback_query() {
        assert_eq!(
            parse_callback("GET /callback?code=abc&state=xyz HTTP/1.1").as_deref(),
            Some("code=abc&state=xyz")
        );
        assert_eq!(
            parse_callback("GET /callback HTTP/1.1").as_deref(),
            Some("")
        );
    }

    #[test]
    fn ignores_other_paths_and_methods() {
        assert_eq!(parse_callback("GET /favicon.ico HTTP/1.1"), None);
        assert_eq!(parse_callback("POST /callback?code=abc HTTP/1.1"), None);
        assert_eq!(parse_callback(""), None);
    }

    #[tokio::test]
    async fn redirect_uri_points_to_loopback_callback() {
        let server = CallbackServer::bind().await.unwrap();
        let uri = server.redirect_uri();
        assert_eq!(uri.scheme(), "http");
        assert_eq!(uri.host_str(), Some("127.0.0.1"));
        assert_eq!(uri.path(), "/callback");
        assert!(uri.port().is_some());
    }

    #[tokio::test]
    async fn returns_callback_query_after_unrelated_requests() {
        let server = CallbackServer::bind().await.unwrap();
        let port = server.redirect_uri().port().unwrap();

        let browser = async {
            let _idle = TcpStream::connect((Ipv4Addr::LOCALHOST, port))
                .await
                .unwrap();
            let favicon = send(&server, "GET /favicon.ico HTTP/1.1\r\nHost: x\r\n\r\n").await;
            let callback = send(
                &server,
                "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: x\r\n\r\n",
            )
            .await;
            (favicon, callback)
        };
        let (query, (favicon, callback)) = tokio::join!(
            server.wait_for_query("xyz", Duration::from_secs(5)),
            browser
        );

        assert_eq!(query.unwrap(), "code=abc&state=xyz");
        assert!(favicon.starts_with("HTTP/1.1 404"));
        assert!(callback.starts_with("HTTP/1.1 200"));
        // A troca do code ainda não aconteceu: a página não pode prometer que o login deu certo.
        assert!(callback.contains("voltar ao Matrix Messenger"));
        assert!(!callback.contains("concluído"));
    }

    #[tokio::test]
    async fn denied_callback_shows_cancel_page() {
        let server = CallbackServer::bind().await.unwrap();
        let (query, response) = tokio::join!(
            server.wait_for_query("xyz", Duration::from_secs(5)),
            send(
                &server,
                "GET /callback?error=access_denied&state=xyz HTTP/1.1\r\n\r\n"
            ),
        );

        assert_eq!(query.unwrap(), "error=access_denied&state=xyz");
        assert!(response.contains("O login não foi concluído"));
    }

    #[tokio::test]
    async fn ignores_callbacks_with_another_state() {
        let server = CallbackServer::bind().await.unwrap();

        let browser = async {
            let stale = send(&server, "GET /callback?code=old&state=abc HTTP/1.1\r\n\r\n").await;
            let empty = send(&server, "GET /callback HTTP/1.1\r\n\r\n").await;
            let valid = send(&server, "GET /callback?code=new&state=xyz HTTP/1.1\r\n\r\n").await;
            (stale, empty, valid)
        };
        let (query, (stale, empty, valid)) = tokio::join!(
            server.wait_for_query("xyz", Duration::from_secs(5)),
            browser
        );

        assert_eq!(query.unwrap(), "code=new&state=xyz");
        assert!(stale.starts_with("HTTP/1.1 400"));
        assert!(empty.starts_with("HTTP/1.1 400"));
        assert!(valid.starts_with("HTTP/1.1 200"));
    }

    #[tokio::test]
    async fn times_out_without_callback() {
        let server = CallbackServer::bind().await.unwrap();
        let result = server
            .wait_for_query("xyz", Duration::from_millis(50))
            .await;
        assert!(matches!(result, Err(CallbackError::TimedOut)));
    }
}
