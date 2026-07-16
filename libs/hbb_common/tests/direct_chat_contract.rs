use hbb_common::{
    protos::message::{login_request, ChatSession, LoginRequest},
    rendezvous_proto::ConnType,
};

#[test]
fn chat_login_is_a_distinct_persistent_session_type() {
    let mut login = LoginRequest::new();
    login.set_chat(ChatSession {
        persistent: true,
        direct_only: true,
        ..Default::default()
    });

    assert!(matches!(
        login.union,
        Some(login_request::Union::Chat(ChatSession {
            persistent: true,
            direct_only: true,
            ..
        }))
    ));
    assert_eq!(ConnType::CHAT as i32, 6);
}
