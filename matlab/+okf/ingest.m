function ing = ingest(source)
%INGEST Ingest from a bundle directory, local tar/zip archive, or git URL.
if exist(source, 'dir') == 7
    ing = okf.ingest_bundle(okf.read_bundle(source, 'dir'));
    return;
end
f = okf.fetch(source);
cleanup = onCleanup(@() f.cleanup());
ing = okf.ingest_bundle(okf.read_bundle(f.dir, f.kind));
end
