function hex = sha1_hex(bytes)
%SHA1_HEX Pure-M SHA-1 (FIPS 180-1) of a uint8 vector -> lowercase hex.
%   No Java, no toolboxes -- portable across MATLAB and Octave. Correctness
%   locked by the conformance fixture (content_hashes in expected/store.json)
%   and known-vector checks in check_matlab.
bytes = uint8(bytes(:))';
len_bits = uint64(numel(bytes)) * 8;
% pad: 0x80, zeros to 56 mod 64, then 8-byte big-endian bit length
pad_len = mod(56 - mod(numel(bytes) + 1, 64), 64);
msg = [bytes, uint8(128), zeros(1, pad_len, 'uint8'), len_be(len_bits)];

h = uint32([hex2dec('67452301'), hex2dec('EFCDAB89'), hex2dec('98BADCFE'), ...
            hex2dec('10325476'), hex2dec('C3D2E1F0')]);
K = uint32([hex2dec('5A827999'), hex2dec('6ED9EBA1'), ...
            hex2dec('8F1BBCDC'), hex2dec('CA62C1D6')]);

for blk = 1:64:numel(msg)
    chunk = msg(blk:blk + 63);
    w = zeros(1, 80, 'uint32');
    for i = 1:16
        b4 = uint32(chunk(4 * i - 3:4 * i));
        w(i) = bitor(bitor(bitshift(b4(1), 24), bitshift(b4(2), 16)), ...
                     bitor(bitshift(b4(3), 8), b4(4)));
    end
    for i = 17:80
        w(i) = rol(bitxor(bitxor(w(i - 3), w(i - 8)), bitxor(w(i - 14), w(i - 16))), 1);
    end
    a = h(1); b = h(2); c = h(3); d = h(4); e = h(5);
    for i = 1:80
        if i <= 20
            f = bitor(bitand(b, c), bitand(bitcmp(b), d)); k = K(1);
        elseif i <= 40
            f = bitxor(bitxor(b, c), d); k = K(2);
        elseif i <= 60
            f = bitor(bitor(bitand(b, c), bitand(b, d)), bitand(c, d)); k = K(3);
        else
            f = bitxor(bitxor(b, c), d); k = K(4);
        end
        t = add32(add32(add32(rol(a, 5), f), add32(e, k)), w(i));
        e = d; d = c; c = rol(b, 30); b = a; a = t;
    end
    h = [add32(h(1), a), add32(h(2), b), add32(h(3), c), add32(h(4), d), add32(h(5), e)];
end
hex = lower(reshape(dec2hex(h, 8)', 1, []));
end

function out = rol(v, n)
out = bitor(bitshift(v, n), bitshift(v, n - 32));
end

function out = add32(a, b)
out = uint32(mod(double(a) + double(b), 4294967296));
end

function b = len_be(len_bits)
b = zeros(1, 8, 'uint8');
v = double(len_bits);
for i = 8:-1:1
    b(i) = uint8(mod(v, 256));
    v = floor(v / 256);
end
end
