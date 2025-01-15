package com.comet.opik.domain;

import com.comet.opik.api.error.InvalidUUIDVersionException;
import io.dropwizard.jersey.errors.ErrorMessage;
import reactor.core.publisher.Mono;

import java.util.UUID;

import static jakarta.ws.rs.core.Response.Status.BAD_REQUEST;

public interface IdGenerator {

    UUID generateId();

    static Mono<UUID> validateVersionAsync(UUID id, String resource) {
        if (id.version() != 7) {
            return Mono.error(
                    new InvalidUUIDVersionException(
                            new ErrorMessage(BAD_REQUEST.getStatusCode(),
                                    "%s id must be a version 7 UUID".formatted(resource))));
        }

        return Mono.just(id);
    }

    static void validateVersion(UUID id, String resource) {
        if (id.version() != 7)
            throw new InvalidUUIDVersionException(
                    new ErrorMessage(BAD_REQUEST.getStatusCode(),
                            "%s id must be a version 7 UUID".formatted(resource)));
    }
}
