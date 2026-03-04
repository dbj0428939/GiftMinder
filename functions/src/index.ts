import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

type NotificationPreferences = {
  enableNotifications?: boolean;
  daysInAdvance?: number;
  forumUpdatesEnabled?: boolean;
  mutedForumEventIds?: string[];
};

type UserDoc = {
  fcmToken?: string;
  notificationPreferences?: NotificationPreferences;
  userId?: string;
};

type NetworkEventDoc = {
  organizerId: string;
  organizerName?: string;
  title: string;
  details?: string;
  theme?: string;
  startAt: admin.firestore.Timestamp;
  locationName?: string;
  visibility?: string;
  invitedUserHandles?: string[];
  inviteStatuses?: Record<string, string>;
  attendingUserIds?: string[];
  attendingNames?: string[];
  createdAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;
};

type ContactDoc = {
  userId: string;
  name: string;
  phoneNumber?: string;
  email?: string;
  relationship?: string;
  imageUrl?: string;
  birthday?: admin.firestore.Timestamp;
  anniversary?: admin.firestore.Timestamp;
  notes?: string;
  giftCount?: number;
  purchasedGiftCount?: number;
  createdAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;
};

type NotificationSentRecord = {
  userId: string;
  contactId: string;
  type: "birthday" | "anniversary";
  sentAt: admin.firestore.Timestamp;
};

type GiftDoc = {
  title: string;
  price?: number;
  url?: string;
  status: "wishlist" | "purchased";
  notes?: string;
  createdAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;
};

export const onContactCreated = functions.firestore
  .document("contacts/{contactId}")
  .onCreate(async (snapshot, context) => {
    const contactId = context.params.contactId as string;
    const data = snapshot.data() as ContactDoc;

    const userId = String(data.userId ?? "").trim();
    if (!userId) {
      await snapshot.ref.delete();
      functions.logger.warn("Contact created without userId, deleted", { contactId });
      return;
    }

    const name = String(data.name ?? "").trim();
    if (!name) {
      await snapshot.ref.delete();
      functions.logger.warn("Contact created without name, deleted", { contactId });
      return;
    }

    const updates: Record<string, unknown> = {
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await snapshot.ref.update(updates);
  });

export const onContactUpdated = functions.firestore
  .document("contacts/{contactId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() as ContactDoc;
    const after = change.after.data() as ContactDoc;

    const userIdBefore = String(before.userId ?? "").trim();
    const userIdAfter = String(after.userId ?? "").trim();

    if (!userIdAfter || (userIdBefore && userIdBefore !== userIdAfter)) {
      functions.logger.error("Contact userId changed or cleared, reverting", {
        contactId: context.params.contactId,
        before: userIdBefore,
        after: userIdAfter,
      });
      await change.after.ref.update({ userId: userIdBefore });
      return;
    }

    const nameBefore = String(before.name ?? "").trim();
    const nameAfter = String(after.name ?? "").trim();

    if (!nameAfter && nameBefore) {
      functions.logger.warn("Contact name cleared, reverting", {
        contactId: context.params.contactId,
      });
      await change.after.ref.update({ name: nameBefore });
      return;
    }

    const beforeBirthday = before.birthday?.toMillis?.() ?? null;
    const afterBirthday = after.birthday?.toMillis?.() ?? null;
    const beforeAnniversary = before.anniversary?.toMillis?.() ?? null;
    const afterAnniversary = after.anniversary?.toMillis?.() ?? null;

    const hasMeaningfulChange =
      before.userId !== after.userId ||
      before.name !== after.name ||
      before.phoneNumber !== after.phoneNumber ||
      before.email !== after.email ||
      before.relationship !== after.relationship ||
      before.imageUrl !== after.imageUrl ||
      before.notes !== after.notes ||
      beforeBirthday !== afterBirthday ||
      beforeAnniversary !== afterAnniversary;

    if (!hasMeaningfulChange) {
      return;
    }

    const updates: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await change.after.ref.update(updates);
  });

export const checkUpcomingDates = functions.pubsub
  .schedule("every day 09:00")
  .timeZone("America/New_York")
  .onRun(async () => {
    const usersSnapshot = await db.collection("users").get();
    let notificationsSent = 0;
    let errors = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data() as UserDoc | undefined;

      if (!userData?.notificationPreferences?.enableNotifications) {
        continue;
      }

      const daysInAdvance = userData.notificationPreferences.daysInAdvance ?? 1;

      try {
        const sent = await checkUserContactDates(userId, daysInAdvance);
        notificationsSent += sent;
      } catch (err) {
        functions.logger.error("Error checking contact dates for user", {
          userId,
          error: err instanceof Error ? err.message : String(err),
        });
        errors++;
      }
    }

    functions.logger.info("Completed checkUpcomingDates", {
      notificationsSent,
      errors,
      totalUsers: usersSnapshot.size,
    });
    return null;
  });

async function checkUserContactDates(userId: string, daysInAdvance: number): Promise<number> {
  const contactsSnapshot = await db
    .collection("contacts")
    .where("userId", "==", userId)
    .get();

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const targetDate = new Date(today);
  targetDate.setDate(targetDate.getDate() + daysInAdvance);

  let sent = 0;

  for (const contactDoc of contactsSnapshot.docs) {
    const contact = contactDoc.data() as ContactDoc;
    const contactId = contactDoc.id;

    if (contact.birthday) {
      const isBirthdayUpcoming = isDateUpcoming(
        contact.birthday.toDate(),
        targetDate,
      );
      if (isBirthdayUpcoming) {
        const alreadySent = await hasNotificationBeenSent(userId, contactId, "birthday");
        if (!alreadySent) {
          await sendDateNotification(userId, contact.name, "birthday", daysInAdvance);
          await recordNotificationSent(userId, contactId, "birthday");
          sent++;
        }
      }
    }

    if (contact.anniversary) {
      const isAnniversaryUpcoming = isDateUpcoming(
        contact.anniversary.toDate(),
        targetDate,
      );
      if (isAnniversaryUpcoming) {
        const alreadySent = await hasNotificationBeenSent(userId, contactId, "anniversary");
        if (!alreadySent) {
          await sendDateNotification(
            userId,
            contact.name,
            "anniversary",
            daysInAdvance,
          );
          await recordNotificationSent(userId, contactId, "anniversary");
          sent++;
        }
      }
    }
  }

  return sent;
}

function isDateUpcoming(eventDate: Date, targetDate: Date): boolean {
  const eventMonth = eventDate.getMonth();
  const eventDay = eventDate.getDate();

  const targetMonth = targetDate.getMonth();
  const targetDay = targetDate.getDate();

  return eventMonth === targetMonth && eventDay === targetDay;
}

async function hasNotificationBeenSent(
  userId: string,
  contactId: string,
  type: "birthday" | "anniversary",
): Promise<boolean> {
  const recordId = buildNotificationRecordId(userId, contactId, type, new Date());
  const snapshot = await db.collection("notificationsSent").doc(recordId).get();
  return snapshot.exists;
}

async function recordNotificationSent(
  userId: string,
  contactId: string,
  type: "birthday" | "anniversary",
): Promise<void> {
  const recordId = buildNotificationRecordId(userId, contactId, type, new Date());
  await db.collection("notificationsSent").doc(recordId).set({
    userId,
    contactId,
    type,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
  } as NotificationSentRecord, {merge: true});
}

function buildNotificationRecordId(
  userId: string,
  contactId: string,
  type: "birthday" | "anniversary",
  date: Date,
): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${userId}_${contactId}_${type}_${year}${month}${day}`;
}

async function sendDateNotification(
  userId: string,
  contactName: string,
  type: "birthday" | "anniversary",
  daysInAdvance: number,
): Promise<void> {
  const userDoc = await db.collection("users").doc(userId).get();
  const user = userDoc.data() as UserDoc | undefined;

  if (!user) {
    return;
  }

  const token = String(user.fcmToken ?? "").trim();
  if (!token) {
    return;
  }

  const typeLabel = type === "birthday" ? "Birthday" : "Anniversary";
  let title = "";
  let body = "";

  if (daysInAdvance === 0) {
    title = `${typeLabel} Today!`;
    body = `Today is ${contactName}'s ${type}.`;
  } else {
    title = `Upcoming ${typeLabel}`;
    body = `${contactName}'s ${type} is in ${daysInAdvance} day${daysInAdvance === 1 ? "" : "s"}.`;
  }

  const message: admin.messaging.Message = {
    token,
    notification: {
      title,
      body,
    },
    data: {
      notificationType: "contact_date_reminder",
      dateType: type,
      contactName,
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  };

  try {
    await messaging.send(message);
  } catch (error) {
    if (isInvalidFcmTokenError(error)) {
      await db.collection("users").doc(userId).set({
        fcmToken: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    functions.logger.warn("Failed to send date notification", {
      userId,
      contactName,
      type,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

export const onAuthUserCreated = functions.auth.user().onCreate(async (user) => {
  const userRef = db.collection("users").doc(user.uid);
  const snapshot = await userRef.get();
  const existing = snapshot.data() ?? {};

  const existingDisplayName = String(existing.displayName ?? existing.name ?? "").trim();
  const resolvedDisplayName = existingDisplayName || deriveDisplayName(user.displayName, user.email);

  const payload: Record<string, unknown> = {
    uid: user.uid,
    displayName: resolvedDisplayName,
    name: resolvedDisplayName,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (user.email) {
    payload.email = user.email;
  }

  if (!snapshot.exists || !existing.createdAt) {
    payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await userRef.set(payload, {merge: true});
});

export const updateFcmToken = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const fcmToken = String(data?.fcmToken ?? "").trim();
  if (!fcmToken) {
    throw new functions.https.HttpsError("invalid-argument", "fcmToken is required");
  }

  await db.collection("users").doc(context.auth.uid).set(
    {
      fcmToken,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { success: true };
});

function deriveDisplayName(displayName: string | null | undefined, email: string | null | undefined): string {
  const trimmedDisplayName = displayName ? String(displayName).trim() : "";
  if (trimmedDisplayName) {
    return trimmedDisplayName;
  }

  void email;

  return "GiftMinder User";
}

export const updateNotificationPreferences = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const enableNotifications = Boolean(data?.enableNotifications);
  const rawDays = Number(data?.daysInAdvance ?? 1);
  const parsedDays = Number.isFinite(rawDays) ? Math.trunc(rawDays) : 1;
  const daysInAdvance = Math.min(30, Math.max(0, parsedDays));
  const forumUpdatesEnabled = data?.forumUpdatesEnabled === undefined ? true : Boolean(data?.forumUpdatesEnabled);

  await db.collection("users").doc(context.auth.uid).set(
    {
      notificationPreferences: {
        enableNotifications,
        daysInAdvance,
        forumUpdatesEnabled,
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { success: true };
});

type ProfileModerationInput = {
  bio?: string;
  imageMeta?: {
    byteSize?: number;
    width?: number;
    height?: number;
  };
};

export const moderateProfileContent = functions.https.onCall(async (data: ProfileModerationInput, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const bio = String(data?.bio ?? "").trim();
  const imageMeta = data?.imageMeta ?? {};
  const byteSize = Number(imageMeta.byteSize ?? 0);
  const width = Number(imageMeta.width ?? 0);
  const height = Number(imageMeta.height ?? 0);

  const reasons: string[] = [];
  const loweredBio = bio.toLowerCase();

  if (bio.length > 240) {
    reasons.push("Bio exceeds the 240 character limit.");
  }

  const linkPattern = /(https?:\/\/|www\.|\b[a-z0-9.-]+\.[a-z]{2,}(\/|\b))/i;
  if (linkPattern.test(bio)) {
    reasons.push("Bio cannot include links.");
  }

  const blockedTerms = ["porn", "nude", "xxx", "escort", "hate", "slur"];
  if (blockedTerms.some((term) => loweredBio.includes(term))) {
    reasons.push("Bio includes blocked language.");
  }

  if (byteSize > 5_000_000) {
    reasons.push("Image file is too large.");
  }

  if (width > 0 && height > 0) {
    const aspect = Math.max(width, height) / Math.max(1, Math.min(width, height));
    if (aspect > 4) {
      reasons.push("Image aspect ratio is not supported.");
    }
    if (width < 40 || height < 40) {
      reasons.push("Image resolution is too low.");
    }
  }

  const allowed = reasons.length === 0;
  return {
    allowed,
    reasons,
    normalizedBio: bio,
  };
});

export const reportProfile = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
  }

  const reportedUid = String(data?.reportedUid ?? "").trim();
  const reason = String(data?.reason ?? "").trim().toLowerCase();
  const details = String(data?.details ?? "").trim();

  if (!reportedUid) {
    throw new functions.https.HttpsError("invalid-argument", "reportedUid is required");
  }

  if (reportedUid === context.auth.uid) {
    throw new functions.https.HttpsError("invalid-argument", "Cannot report your own profile");
  }

  const allowedReasons = new Set([
    "inappropriate_photo",
    "inappropriate_bio",
    "harassment",
    "impersonation",
    "other",
  ]);

  const normalizedReason = allowedReasons.has(reason) ? reason : "other";

  await db.collection("profileReports").add({
    reporterUid: context.auth.uid,
    reportedUid,
    reason: normalizedReason,
    details: details.slice(0, 500),
    status: "open",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

export const onGiftCreated = functions.firestore
  .document("contacts/{contactId}/gifts/{giftId}")
  .onCreate(async (snapshot, context) => {
    const contactId = context.params.contactId as string;
    const giftId = context.params.giftId as string;
    const data = snapshot.data() as GiftDoc;

    // Validate required fields
    const title = String(data.title ?? "").trim();
    if (!title) {
      await snapshot.ref.delete();
      functions.logger.warn("Gift created without title, deleted", { contactId, giftId });
      return;
    }

    // Validate price if provided
    if (data.price !== undefined && data.price !== null) {
      const price = Number(data.price);
      if (!Number.isFinite(price) || price < 0) {
        await snapshot.ref.delete();
        functions.logger.warn("Gift created with invalid price, deleted", {
          contactId,
          giftId,
          price: data.price,
        });
        return;
      }
    }

    // Validate URL if provided
    if (data.url) {
      const urlStr = String(data.url).trim();
      if (urlStr && !isValidUrl(urlStr)) {
        await snapshot.ref.delete();
        functions.logger.warn("Gift created with invalid URL, deleted", {
          contactId,
          giftId,
          url: urlStr,
        });
        return;
      }
    }

    const status = String(data.status ?? "wishlist").trim().toLowerCase();
    if (status !== "wishlist" && status !== "purchased") {
      await snapshot.ref.delete();
      functions.logger.warn("Gift created with invalid status, deleted", {
        contactId,
        giftId,
        status,
      });
      return;
    }

    // Set timestamps and default status
    const updates: Record<string, unknown> = {
      status,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await snapshot.ref.update(updates);

    // Increment gift counters on contact
    const purchasedIncrement = status === "purchased" ? 1 : 0;
    await db.collection("contacts").doc(contactId).update({
      giftCount: admin.firestore.FieldValue.increment(1),
      purchasedGiftCount: admin.firestore.FieldValue.increment(purchasedIncrement),
    });
  });

export const onGiftUpdated = functions.firestore
  .document("contacts/{contactId}/gifts/{giftId}")
  .onUpdate(async (change, context) => {
    const contactId = context.params.contactId as string;
    const giftId = context.params.giftId as string;
    const before = change.before.data() as GiftDoc;
    const after = change.after.data() as GiftDoc;

    // Validate title didn't get cleared
    const titleAfter = String(after.title ?? "").trim();
    if (!titleAfter && before.title) {
      functions.logger.warn("Gift title cleared, reverting", { contactId, giftId });
      await change.after.ref.update({ title: before.title });
      return;
    }

    // Validate price
    if (after.price !== undefined && after.price !== null) {
      const price = Number(after.price);
      if (!Number.isFinite(price) || price < 0) {
        functions.logger.warn("Gift updated with invalid price, reverting", {
          contactId,
          giftId,
        });
        await change.after.ref.update({ price: before.price ?? null });
        return;
      }
    }

    // Validate URL
    if (after.url) {
      const urlStr = String(after.url).trim();
      if (urlStr && !isValidUrl(urlStr)) {
        functions.logger.warn("Gift updated with invalid URL, reverting", {
          contactId,
          giftId,
        });
        await change.after.ref.update({ url: before.url ?? null });
        return;
      }
    }

    const normalizedStatusAfter = String(after.status ?? "wishlist").trim().toLowerCase();
    if (normalizedStatusAfter !== "wishlist" && normalizedStatusAfter !== "purchased") {
      functions.logger.warn("Gift updated with invalid status, reverting", {
        contactId,
        giftId,
      });
      await change.after.ref.update({ status: before.status ?? "wishlist" });
      return;
    }

    // Track purchase status change
    const statusBefore = String(before.status ?? "wishlist").trim().toLowerCase();
    const statusAfter = normalizedStatusAfter;

    const hasMeaningfulChange =
      before.title !== after.title ||
      before.price !== after.price ||
      before.url !== after.url ||
      before.notes !== after.notes ||
      statusBefore !== statusAfter;

    if (!hasMeaningfulChange) {
      return;
    }

    const updates: Record<string, unknown> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Update contact's purchase count if status changed
    if (statusBefore !== statusAfter) {
      const contactRef = db.collection("contacts").doc(contactId);
      const increment = statusAfter === "purchased" ? 1 : -1;

      await db.runTransaction(async (tx) => {
        const contactSnapshot = await tx.get(contactRef);
        if (!contactSnapshot.exists) {
          return;
        }

        const contact = contactSnapshot.data() as ContactDoc | undefined;
        const currentPurchased = Number(contact?.purchasedGiftCount ?? 0);
        const nextPurchased = Math.max(0, currentPurchased + increment);
        tx.update(contactRef, { purchasedGiftCount: nextPurchased });
      });
    }

    await change.after.ref.update(updates);
  });

export const onGiftDeleted = functions.firestore
  .document("contacts/{contactId}/gifts/{giftId}")
  .onDelete(async (snapshot, context) => {
    const contactId = context.params.contactId as string;
    const data = snapshot.data() as GiftDoc;

    // Decrement gift count on contact
    const contactRef = db.collection("contacts").doc(contactId);
    await db.runTransaction(async (tx) => {
      const contactSnapshot = await tx.get(contactRef);
      if (!contactSnapshot.exists) {
        return;
      }

      const contact = contactSnapshot.data() as ContactDoc | undefined;
      const giftCount = Number(contact?.giftCount ?? 0);
      const purchasedCount = Number(contact?.purchasedGiftCount ?? 0);
      const giftWasPurchased = String(data.status ?? "wishlist").trim().toLowerCase() === "purchased";

      const updates: Record<string, unknown> = {
        giftCount: Math.max(0, giftCount - 1),
      };

      if (giftWasPurchased) {
        updates.purchasedGiftCount = Math.max(0, purchasedCount - 1);
      }

      tx.update(contactRef, updates);
    });
  });

export const markGiftPurchased = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated",
    );
  }

  const contactId = String(data?.contactId ?? "").trim();
  const giftId = String(data?.giftId ?? "").trim();
  const purchased = Boolean(data?.purchased);

  if (!contactId || !giftId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "contactId and giftId are required",
    );
  }

  const giftRef = db.collection("contacts").doc(contactId).collection("gifts").doc(giftId);
  const contactRef = db.collection("contacts").doc(contactId);
  const contactSnapshot = await contactRef.get();

  if (!contactSnapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Contact not found");
  }

  const contactData = contactSnapshot.data() as ContactDoc | undefined;
  if (!contactData || String(contactData.userId ?? "").trim() !== context.auth.uid) {
    throw new functions.https.HttpsError("permission-denied", "Not allowed to modify this gift");
  }

  const giftSnapshot = await giftRef.get();

  if (!giftSnapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Gift not found");
  }

  const giftData = giftSnapshot.data() as GiftDoc | undefined;
  if (!giftData) {
    throw new functions.https.HttpsError("not-found", "Gift data not found");
  }

  const newStatus = purchased ? "purchased" : "wishlist";
  const oldStatus = giftData.status || "wishlist";

  if (oldStatus === newStatus) {
    return { success: true, updated: false };
  }

  await giftRef.update({
    status: newStatus,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true, updated: true, status: newStatus };
});

function isValidUrl(urlString: string): boolean {
  try {
    const parsed = new URL(urlString);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

export const onNetworkEventCreated = functions.firestore
  .document("networkEvents/{eventId}")
  .onCreate(async (snapshot, context) => {
    const eventId = context.params.eventId as string;
    const event = snapshot.data() as NetworkEventDoc;

    const recipientUids = await resolveRecipients(event);
    if (recipientUids.length === 0) {
      return null;
    }

    const startLabel = formatStartAt(event.startAt);
    const title = `You're invited: ${event.title}`;
    const body = `${event.organizerName ?? "A user"} invited you • ${startLabel}`;

    await sendEventPush(recipientUids, {
      title,
      body,
      eventId,
      notificationType: "network_event_invite",
    });

    return null;
  });

export const onNetworkEventUpdated = functions.firestore
  .document("networkEvents/{eventId}")
  .onUpdate(async (change, context) => {
    const eventId = context.params.eventId as string;
    const before = change.before.data() as NetworkEventDoc;
    const after = change.after.data() as NetworkEventDoc;

    if (!isMeaningfulEventUpdate(before, after)) {
      return null;
    }

    const recipientUids = await resolveRecipients(after);
    if (recipientUids.length === 0) {
      return null;
    }

    const title = `Event updated: ${after.title}`;
    const body = `${after.organizerName ?? "Organizer"} changed event details. Tap to review.`;

    await sendEventPush(recipientUids, {
      title,
      body,
      eventId,
      notificationType: "network_event_update",
    });

    return null;
  });

export const onNetworkInviteResponseUpdated = functions.firestore
  .document("networkEvents/{eventId}")
  .onUpdate(async (change, context) => {
    const eventId = context.params.eventId as string;
    const before = change.before.data() as NetworkEventDoc;
    const after = change.after.data() as NetworkEventDoc;

    const responseChange = findInviteResponseChange(before.inviteStatuses ?? {}, after.inviteStatuses ?? {});
    if (!responseChange) {
      return null;
    }

    const organizerUid = String(after.organizerId ?? "").trim();
    if (!organizerUid) {
      return null;
    }

    const responderName = await resolveDisplayNameFromHandle(responseChange.handle);
    const title = `Invite response: ${after.title}`;
    const body = `${responderName} responded ${responseChange.nextStatus} to your event.`;

    await sendSingleUserPush(organizerUid, {
      title,
      body,
      eventId,
      notificationType: "network_event_invite_response",
    });

    return null;
  });

export const onNetworkEventForumMessageCreated = functions.firestore
  .document("networkEvents/{eventId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const eventId = String(context.params.eventId ?? "").trim();
    if (!eventId) {
      return null;
    }

    const messageData = snapshot.data() as {authorName?: string; authorUserId?: string; text?: string} | undefined;
    const authorUid = String(messageData?.authorUserId ?? "").trim();

    const eventDoc = await db.collection("networkEvents").doc(eventId).get();
    if (!eventDoc.exists) {
      return null;
    }

    const event = eventDoc.data() as NetworkEventDoc;
    const allRecipients = new Set<string>(await resolveRecipients(event));
    const organizerUid = String(event.organizerId ?? "").trim();
    if (organizerUid) {
      allRecipients.add(organizerUid);
    }
    const recipientUids = Array.from(allRecipients).filter((uid) => uid !== authorUid);
    if (recipientUids.length === 0) {
      return null;
    }

    const title = `New forum message: ${event.title}`;
    const author = String(messageData?.authorName ?? "").trim() || "Someone";
    const text = String(messageData?.text ?? "").trim();
    const body = text ? `${author}: ${text.substring(0, 120)}` : `${author} posted in the forum.`;

    await sendEventPush(recipientUids, {
      title,
      body,
      eventId,
      notificationType: "network_event_forum",
    });

    return null;
  });

async function resolveRecipients(event: NetworkEventDoc): Promise<string[]> {
  const recipients = new Set<string>();

  for (const uid of event.attendingUserIds ?? []) {
    if (uid && uid !== event.organizerId) {
      recipients.add(uid);
    }
  }

  const handles = (event.invitedUserHandles ?? [])
    .map((value) => normalizeHandle(value))
    .filter((value) => value.length > 0);

  if (handles.length > 0) {
    const usernameDocs = await Promise.all(
      handles.map((handle) => db.collection("usernames").doc(handle).get()),
    );

    for (const doc of usernameDocs) {
      const uid = String(doc.data()?.uid ?? "").trim();
      if (uid && uid !== event.organizerId) {
        recipients.add(uid);
      }
    }
  }

  return Array.from(recipients);
}

function normalizeHandle(value: string): string {
  return String(value ?? "").trim().toLowerCase();
}

function isMeaningfulEventUpdate(before: NetworkEventDoc, after: NetworkEventDoc): boolean {
  const beforeStart = before.startAt?.toMillis?.() ?? 0;
  const afterStart = after.startAt?.toMillis?.() ?? 0;

  return (
    before.title !== after.title ||
    before.details !== after.details ||
    before.theme !== after.theme ||
    before.locationName !== after.locationName ||
    before.visibility !== after.visibility ||
    beforeStart !== afterStart ||
    JSON.stringify(before.invitedUserHandles ?? []) !== JSON.stringify(after.invitedUserHandles ?? [])
  );
}

function formatStartAt(timestamp: admin.firestore.Timestamp): string {
  const date = timestamp?.toDate?.() ?? new Date();
  return date.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

async function sendEventPush(
  recipientUids: string[],
  payload: {
    title: string;
    body: string;
    eventId: string;
    notificationType: "network_event_invite" | "network_event_update" | "network_event_forum";
  },
): Promise<void> {
  const userDocs = await Promise.all(
    recipientUids.map((uid) => db.collection("users").doc(uid).get()),
  );

  const tokenEntries: Array<{ uid: string; token: string }> = [];

  for (let idx = 0; idx < userDocs.length; idx++) {
    const doc = userDocs[idx];
    const uid = recipientUids[idx];
    const user = doc.data() as UserDoc | undefined;
    if (!user) {
      continue;
    }

    if (user.notificationPreferences?.enableNotifications === false) {
      continue;
    }

    if (payload.notificationType === "network_event_forum") {
      if (user.notificationPreferences?.forumUpdatesEnabled === false) {
        continue;
      }
      const muted = user.notificationPreferences?.mutedForumEventIds ?? [];
      if (Array.isArray(muted) && muted.includes(payload.eventId)) {
        continue;
      }
    }

    const token = String(user.fcmToken ?? "").trim();
    if (token) {
      tokenEntries.push({uid, token});
    }
  }

  if (tokenEntries.length === 0) {
    return;
  }

  const tokens = tokenEntries.map((entry) => entry.token);

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: {
      eventId: payload.eventId,
      notificationType: payload.notificationType,
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  };

  const response = await messaging.sendEachForMulticast(message);

  if (response.failureCount > 0) {
    const staleUids = new Set<string>();

    const failed = response.responses
      .map((r, idx) => ({ r, idx }))
      .filter(({ r }) => !r.success)
      .map(({ r, idx }) => {
        const uid = tokenEntries[idx]?.uid;
        if (uid && isInvalidFcmTokenError(r.error)) {
          staleUids.add(uid);
        }
        return { token: tokens[idx], error: r.error?.message };
      });

    functions.logger.warn("Some event notifications failed", failed);

    if (staleUids.size > 0) {
      await Promise.all(
        Array.from(staleUids).map((uid) => db.collection("users").doc(uid).set({
          fcmToken: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true})),
      );
    }
  }
}

function findInviteResponseChange(
  before: Record<string, string>,
  after: Record<string, string>,
): { handle: string; prevStatus: string; nextStatus: string } | null {
  const handles = new Set<string>([...Object.keys(before), ...Object.keys(after)]);
  for (const handle of handles) {
    const prev = String(before[handle] ?? "pending").toLowerCase();
    const next = String(after[handle] ?? "pending").toLowerCase();
    if (prev !== next) {
      return { handle, prevStatus: prev, nextStatus: next };
    }
  }
  return null;
}

async function resolveDisplayNameFromHandle(handle: string): Promise<string> {
  const normalized = normalizeHandle(handle);
  if (!normalized) {
    return "Someone";
  }

  const usernameDoc = await db.collection("usernames").doc(normalized).get();
  const uid = String(usernameDoc.data()?.uid ?? "").trim();
  if (!uid) {
    return `@${normalized}`;
  }

  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.data() as Record<string, unknown> | undefined;
  const displayName = String(userData?.displayName ?? userData?.userName ?? "").trim();

  return displayName || `@${normalized}`;
}

async function sendSingleUserPush(
  recipientUid: string,
  payload: {
    title: string;
    body: string;
    eventId: string;
    notificationType: "network_event_invite_response";
  },
): Promise<void> {
  const userDoc = await db.collection("users").doc(recipientUid).get();
  const user = userDoc.data() as UserDoc | undefined;
  if (!user) {
    return;
  }

  if (user.notificationPreferences?.enableNotifications === false) {
    return;
  }

  const token = String(user.fcmToken ?? "").trim();
  if (!token) {
    return;
  }

  const message: admin.messaging.Message = {
    token,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: {
      eventId: payload.eventId,
      notificationType: payload.notificationType,
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  };

  try {
    await messaging.send(message);
  } catch (error) {
    if (isInvalidFcmTokenError(error)) {
      await db.collection("users").doc(recipientUid).set({
        fcmToken: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    functions.logger.warn("Failed to send organizer invite response notification", {
      recipientUid,
      error,
    });
  }
}

function isInvalidFcmTokenError(error: unknown): boolean {
  const code = String((error as {code?: unknown})?.code ?? "").toLowerCase();
  return code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token";
}
