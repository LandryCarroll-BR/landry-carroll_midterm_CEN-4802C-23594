package org.landrycarroll.landrycarroll_midterm_cen4802c23594.controllers;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
public class IncidentSimulationController {
    private static final Logger log = LoggerFactory.getLogger(IncidentSimulationController.class);

    private final boolean incidentSimulationEnabled;
    private final long crashDelayMs;

    public IncidentSimulationController(
        @Value("${incident.simulation.enabled:false}") boolean incidentSimulationEnabled,
        @Value("${incident.simulation.crash-delay-ms:750}") long crashDelayMs
    ) {
        this.incidentSimulationEnabled = incidentSimulationEnabled;
        this.crashDelayMs = crashDelayMs;
    }

    @PostMapping("/simulate/error")
    public ResponseEntity<String> simulateError() {
        if (!incidentSimulationEnabled) {
            throw new ResponseStatusException(NOT_FOUND);
        }

        log.error("Simulated application error requested.");
        throw new IllegalStateException("Simulated application error for incident testing.");
    }

    @PostMapping("/simulate/crash")
    public ResponseEntity<String> simulateCrash() {
        if (!incidentSimulationEnabled) {
            throw new ResponseStatusException(NOT_FOUND);
        }

        log.error("Simulated crash requested. The JVM will halt in {} ms.", crashDelayMs);

        Thread crashThread = new Thread(() -> {
            try {
                Thread.sleep(crashDelayMs);
            } catch (InterruptedException interruptedException) {
                Thread.currentThread().interrupt();
                log.warn("Simulated crash thread interrupted before halt.");
                return;
            }

            Runtime.getRuntime().halt(1);
        }, "incident-simulation-crash");
        crashThread.setDaemon(false);
        crashThread.start();

        return ResponseEntity.accepted().body("Simulated crash scheduled.");
    }
}
