import UserActivityStreamRoute from "discourse/routes/user-activity-stream";

export default UserActivityStreamRoute.extend({
  userActionType: 15,
  noContentHelpKey: "endorsed.no_endorsed_solutions"
});
