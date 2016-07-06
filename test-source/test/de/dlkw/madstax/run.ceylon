import ceylon.buffer.charset {
    utf8
}
import ceylon.test {
    test,
    assertEquals
}

import de.dlkw.madstax {
    XMLEventReader,
    ParseError,
    PositionPushbackSource
}

test
shared void readEmpty()
{
    String xml = " a            b  ";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(xmlBuf);
    value ev = r.next();
    if (is ParseError ev) {
        print("l``r.line``/c``r.column``: ``ev.msg``");
    }
    assertEquals(ev, finished);
}

test
shared void readSimple()
{
    String xml = " \t<!--abc-->\n  <!--  xycuc --> <element  a='n' x='b'/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(xmlBuf);
    while (!is Finished ev = r.next()) {
        if (is ParseError ev) {
            print("l``r.line``/c``r.column``: ``ev.msg``");
            return;
        }
        print("l``r.line``/c``r.column``: ``ev``");
    }
}

test
shared void readSimple2()
{
    String xml = " \t<!--abc-->\n <?qwer blablabla{}?> <!--  xycuc --> <element x='&amp;'>kö\n<?a a?>&nana;<!--abc-->&ga; <u jobi:bi:bi=\"gao \" f='&nana;'>ba<![CDATA[text text]]></u></element> <?i i?> <!--end--> ";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(xmlBuf);
    while (!is Finished ev = r.next()) {
        if (is ParseError ev) {
            print("l``r.line``/c``r.column``: ``ev.msg``");
            return;
        }
        print("l``r.line``/c``r.column``: ``ev``");
    }
}

test
shared void readSimple3()
{
    String xml = " \t<!--abc-->\n  <!--  xycuc --> <el<ement>kö&</element>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(xmlBuf);
    while (!is Finished ev = r.next()) {
        if (is ParseError ev) {
            print("l``r.line``/c``r.column``: ``ev.msg``");
            return;
        }
        print("l``r.line``/c``r.column``: ``ev``");
    }
}

test shared void counter1()
{
    value s = "abc\ndef\rghi\r\njkl\n\n1";
    value src = PositionPushbackSource(s.iterator());
    
    assertEquals(src.offset, 0);
    assertEquals(src.line, 0);
    assertEquals(src.column, 0);
    
    assertEquals(src.nextChar(), 'a');
    assertEquals(src.offset, 1);
    assertEquals(src.line, 1);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), 'b');
    assertEquals(src.offset, 2);
    assertEquals(src.line, 1);
    assertEquals(src.column, 2);
    
    assertEquals(src.nextChar(), 'c');
    assertEquals(src.offset, 3);
    assertEquals(src.line, 1);
    assertEquals(src.column, 3);
    
    assertEquals(src.nextChar(), '\{#0a}');
    assertEquals(src.offset, 4);
    assertEquals(src.line, 1);
    assertEquals(src.column, 4);
    
    assertEquals(src.nextChar(), 'd');
    assertEquals(src.offset, 5);
    assertEquals(src.line, 2);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), 'e');
    assertEquals(src.offset, 6);
    assertEquals(src.line, 2);
    assertEquals(src.column, 2);
    
    assertEquals(src.nextChar(), 'f');
    assertEquals(src.offset, 7);
    assertEquals(src.line, 2);
    assertEquals(src.column, 3);
    
    assertEquals(src.nextChar(), '\{#0a}');
    assertEquals(src.offset, 8);
    assertEquals(src.line, 2);
    assertEquals(src.column, 4);
    
    assertEquals(src.nextChar(), 'g');
    assertEquals(src.offset, 9);
    assertEquals(src.line, 3);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), 'h');
    assertEquals(src.offset, 10);
    assertEquals(src.line, 3);
    assertEquals(src.column, 2);
    
    assertEquals(src.nextChar(), 'i');
    assertEquals(src.offset, 11);
    assertEquals(src.line, 3);
    assertEquals(src.column, 3);
    
    assertEquals(src.nextChar(), '\{#0a}');
    assertEquals(src.offset, 13);
    assertEquals(src.line, 3);
    assertEquals(src.column, 4);
    
    assertEquals(src.nextChar(), 'j');
    assertEquals(src.offset, 14);
    assertEquals(src.line, 4);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), 'k');
    assertEquals(src.offset, 15);
    assertEquals(src.line, 4);
    assertEquals(src.column, 2);
    
    assertEquals(src.nextChar(), 'l');
    assertEquals(src.offset, 16);
    assertEquals(src.line, 4);
    assertEquals(src.column, 3);
    
    assertEquals(src.nextChar(), '\{#0a}');
    assertEquals(src.offset, 17);
    assertEquals(src.line, 4);
    assertEquals(src.column, 4);
    
    assertEquals(src.nextChar(), '\{#0a}');
    assertEquals(src.offset, 18);
    assertEquals(src.line, 5);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), '1');
    assertEquals(src.offset, 19);
    assertEquals(src.line, 6);
    assertEquals(src.column, 1);

    assertEquals(src.nextChar(), finished);
}

test shared void counter2()
{
    value s = "\na";
    value src = PositionPushbackSource(s.iterator());
    
    assertEquals(src.offset, 0);
    assertEquals(src.line, 0);
    assertEquals(src.column, 0);
    
    assertEquals(src.nextChar(), '\n');
    assertEquals(src.offset, 1);
    assertEquals(src.line, 1);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), 'a');
    assertEquals(src.offset, 2);
    assertEquals(src.line, 2);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), finished);
}

test shared void counter3()
{
    value s = "\ra";
    value src = PositionPushbackSource(s.iterator());
    
    assertEquals(src.offset, 0);
    assertEquals(src.line, 0);
    assertEquals(src.column, 0);
    
    assertEquals(src.nextChar(), '\n');
    assertEquals(src.offset, 1);
    assertEquals(src.line, 1);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), 'a');
    assertEquals(src.offset, 2);
    assertEquals(src.line, 2);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), finished);
}

test shared void counter4()
{
    value s = "\r\na";
    value src = PositionPushbackSource(s.iterator());
    
    assertEquals(src.offset, 0);
    assertEquals(src.line, 0);
    assertEquals(src.column, 0);
    
    assertEquals(src.nextChar(), '\n');
    assertEquals(src.offset, 2);
    assertEquals(src.line, 1);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), 'a');
    assertEquals(src.offset, 3);
    assertEquals(src.line, 2);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), finished);
}

test shared void counter5()
{
    value s = "\r\n\ra";
    value src = PositionPushbackSource(s.iterator());
    
    assertEquals(src.offset, 0);
    assertEquals(src.line, 0);
    assertEquals(src.column, 0);
    
    assertEquals(src.nextChar(), '\n');
    assertEquals(src.offset, 2);
    assertEquals(src.line, 1);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), '\n');
    assertEquals(src.offset, 3);
    assertEquals(src.line, 2);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), 'a');
    assertEquals(src.offset, 4);
    assertEquals(src.line, 3);
    assertEquals(src.column, 1);
    
    assertEquals(src.nextChar(), finished);
}
