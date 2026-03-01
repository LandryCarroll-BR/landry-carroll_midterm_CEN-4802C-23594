package org.landrycarroll.landrycarroll_midterm_cen4802c23594.controllers;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {
    @GetMapping("/")
    public String home() {
        return "Hello landry-carroll_midterm_CEN-4802C-23594!";
    }
}