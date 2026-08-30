const { createSimpleCrudRoutes } = require('./simple-crud-factory');

module.exports = function eduRoutes(db) {
  return createSimpleCrudRoutes(db, {
    domainType: 'edu',
    table: 'training_records',
    permissionPrefix: 'edu',
    requiredField: { body: 'name', label: '교육명' },
    fields: [
      { body: 'name', column: 'name' },
      { body: 'date', column: 'training_date' },
      { body: 'target', column: 'target_audience' },
      { body: 'nextEduDate', column: 'next_training_date' },
      { body: 'material', column: 'material' },
      { body: 'attendeeNames', column: 'attendee_names' },
      { body: 'absenteeNames', column: 'absentee_names' },
      { body: 'memo', column: 'memo' },
      { body: 'relatedContractor', column: 'related_contractor' },
    ],
  });
};
