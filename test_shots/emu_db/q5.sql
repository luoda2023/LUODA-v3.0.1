.mode column
.headers on
SELECT conversation_id, sender_id, substr(body,1,30) AS body, created_at FROM messages ORDER BY created_at DESC LIMIT 20;
