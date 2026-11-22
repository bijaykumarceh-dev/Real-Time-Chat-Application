const mongoose = require("mongoose");

const readReceiptSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    username: {
      type: String,
      required: true,
      maxlength: 32,
    },
    readAt: {
      type: Date,
      required: true,
    },
  },
  { _id: false },
);

const messageSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    sender: {
      type: String,
      required: true,
      maxlength: 32,
    },
    text: {
      type: String,
      required: true,
      maxlength: 2000,
    },
    room: {
      type: String,
      required: true,
      default: "general",
    },
    readBy: {
      type: [readReceiptSchema],
      default: [],
    },
  },
  { timestamps: true },
);

messageSchema.index({ room: 1, createdAt: -1 });

module.exports = mongoose.models.Message ||
  mongoose.model("Message", messageSchema);
