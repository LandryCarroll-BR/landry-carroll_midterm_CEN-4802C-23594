package org.landrycarroll.landrycarroll_midterm_cen4802c23594.controllers;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {
    @GetMapping("/")
    public String home() {
        return "Hello landry-carroll_final_CEN-4802C-23594!";
    }

    @GetMapping("/greeting")
    public String greeting(String name) {
        return "Hello " + name;
    }

    @GetMapping("/greeting2")
    public String greeting2(String name) {
        return "Hello " + name;
    }

    @GetMapping("/goodbye")
    public String goodbye(String name) {
        return "Goodbye " + name;
    }
}