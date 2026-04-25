package org.landrycarroll.landrycarroll_midterm_cen4802c23594.controllers;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class HelloControllerTest {
    @Test
    void contextLoads() {
        assertTrue(true);
    }

    @Test
    void greeting() {
        HelloController controller = new HelloController();
        assertEquals("Hello landry", controller.greeting("landry"));
    }

    @Test
    void greeting2() {
        HelloController controller = new HelloController();
        assertEquals("Hello landry", controller.greeting2("landry"));
    }

    @Test
    void goodbye() {
       HelloController controller = new HelloController();
       assertEquals("Goodbye landry", controller.goodbye("landry"));
    }
}