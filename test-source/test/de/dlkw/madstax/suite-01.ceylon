import ceylon.collection {
    ArrayList,
    MutableList
}
import ceylon.file {
    parsePath,
    Directory,
    File
}
import ceylon.io {
    newOpenFile
    
}
import ceylon.buffer.charset {
    utf8
}
import de.dlkw.madstax {
    XMLEventReader,
    ParseError,
    EndDocument,
    XMLEvent
}

shared void suite_01()
{
    value root01 = parsePath("/home/dlatt/xmlts/xmlconf/xmltest/not-wf/sa").resource;
    assert (is Directory root01);
    for (path in root01.children("156.xml")) {
        print(path);
        assert (is File path);
        value contents = path.Reader().readBytes(path.size);
        value r = XMLEventReader(contents);
        MutableList<XMLEvent> events = ArrayList<XMLEvent>();
        while (true) {
            try {
                value res = r.next();
                if (is ParseError res) {
                    print(res.msg);
                    break;
                }
                if (is Finished res) {
                    print(events);
                    throw AssertionError("error expected");
                }
                events.add(res);
            }
            catch (Throwable e) {
                e.printStackTrace();
                break;
            }
        }
    }
}