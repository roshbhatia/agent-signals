{
  version = "agent-notify/v1";
  defaults = {
    enabled = true;
    message = "needs your attention";
    sound = "Pop";
    timeoutSeconds = 5;
    cooldownSeconds = 0;
    minDurationSeconds = 0;
    contentImage = false;
  };
  events = {
    approval = {
      message = "needs your approval";
      sound = "Blow";
    };
    idle = {
      message = "is waiting for you";
      cooldownSeconds = 300;
    };
    done = {
      message = "finished its turn";
      sound = "Ping";
      minDurationSeconds = 60;
    };
  };
  profiles.prompt.events.approval = {
    timeoutSeconds = 300;
    contentImage = true;
  };
  agents = { };
  defaultIcon = null;
}
