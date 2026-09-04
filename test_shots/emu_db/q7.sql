.mode column
.headers on
SELECT conversation_id, origin_device_id, direction, kind, substr(text,1,40) AS txt, sender_id, conn_mode, conn_endpoint FROM messages ORDER BY sent_at DESC LIMIT 15;
