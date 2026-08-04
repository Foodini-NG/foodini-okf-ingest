function hex = content_hash(body)
%CONTENT_HASH sha1 hex of the normalized body's UTF-8 bytes (parity lock).
hex = okf.internal.sha1_hex(unicode2native(body, 'UTF-8'));
end
