const { createSimpleCrudRoutes } = require('./simple-crud-factory');

module.exports = function tbmRoutes(db) {
  return createSimpleCrudRoutes(db, {
    domainType: 'tbm',
    table: 'tbm_records',
    permissionPrefix: 'tbm',
    requiredField: { body: 'topic', label: '오늘의 작업내용/TBM 주제' },
    fields: [
      { body: 'date', column: 'tbm_date' },
      { body: 'time', column: 'tbm_time' },
      { body: 'location', column: 'location' },
      { body: 'topic', column: 'topic' },
      { body: 'hazard', column: 'hazard' },
      { body: 'level', column: 'risk_level' },
      { body: 'measure', column: 'measure' },
      { body: 'health', column: 'health_note' },
      { body: 'notice', column: 'notice' },
      { body: 'supervisor', column: 'supervisor' },
      { body: 'relatedContractor', column: 'related_contractor' },
    ],
  });
};
