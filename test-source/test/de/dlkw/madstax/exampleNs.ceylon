import de.dlkw.madstax {
    XMLEventReader,
    StartElement,
    ParseError,
    Characters,
    Comment
}
import ceylon.buffer.charset {
    utf8
}

shared void test1()
{
    String xml = "<a:element xmlns:a='http://dlkw.de' xmlns:bb='http://dlkw.de/x' xmlns='http://dlkw.de/default' a='b' a:a='c' ><a:a xmlns:u='v'/><bb:a xmlns=''/></a:element>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    while (!is Finished x = r.next()) {
        if (is ParseError x) {
            print(x.msg);
            break;
        }
//        assert (is StartElement x);
  //      print(x.namespaceDeclarations);
        print(x);
    }
}

shared void test2()
{
    String xml = "<!-- a test --><ns0:test attr='val' xmlns:ns0='http://madstax.dlkw.de'>some text</ns0:test>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    
    value reader = XMLEventReader(true, xmlBuf);
    while (!is Finished event = reader.next()) {
        if (is ParseError event) {
            print(event.msg);
            break;
        }
        
        print(event);

        switch (event)
        case (is StartElement) {
            print("using defined attributes: ``event.attributes``");
        }
        case (is Characters) {
            print("using text content: ``event.text``");
        }
        case (is Comment) {
            print("using comment: ``event.comment``");
        }
        else {
            // ignore all other events
        }
    }
}
