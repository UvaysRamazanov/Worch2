package com.worch.model.entity;

import com.worch.model.enums.ChoiceStatus;
import com.worch.model.enums.converter.ChoiceStatusConverter;
import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.ZonedDateTime;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

@AllArgsConstructor
@NoArgsConstructor
@Entity
@Table(name = "choice")
@Getter
@Setter
public class Choice {

  @Id
  @GeneratedValue(strategy = GenerationType.UUID)
  @Column(updatable = false, nullable = false, name = "id")
  private UUID id;

  private UUID creatorId;

  private UUID channelId;

  @Column(length = 300)
  private String title;

  @Column(columnDefinition = "TEXT")
  private String description;

//  private byte[] image;

  @Column(name = "is_personal")
  private boolean personal;

  @Convert(converter = ChoiceStatusConverter.class)
  private ChoiceStatus status;

  private ZonedDateTime deadline;

  @CreationTimestamp
  private ZonedDateTime createdAt;
}
