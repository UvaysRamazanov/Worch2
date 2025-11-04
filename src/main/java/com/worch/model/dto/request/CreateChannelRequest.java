package com.worch.model.dto.request;

import com.worch.model.entity.User;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.Builder;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class CreateChannelRequest {

    private String name; // name

    private String description;

    private User owner;

    private Boolean isPrivate;

    private String password;

    private Boolean ageRestricted;

}
