const { createSimpleCrudRoutes } = require('./simple-crud-factory');

module.exports = function contractorRoutes(db) {
  return createSimpleCrudRoutes(db, {
    domainType: 'contractor',
    table: 'contractors',
    permissionPrefix: 'contractor',
    requiredField: [
      { body: 'companyName', label: '업체명' },
      { body: 'repName', label: '담당자명' },
    ],
    fields: [
      { body: 'companyName', column: 'company_name' },
      { body: 'repName', column: 'rep_name' },
      { body: 'phone', column: 'phone' },
      { body: 'workType', column: 'work_type' },
      { body: 'contractStart', column: 'contract_start' },
      { body: 'contractEnd', column: 'contract_end' },
      { body: 'insuranceStatus', column: 'insurance_status' },
      { body: 'safetyEduDate', column: 'safety_edu_date' },
      { body: 'evaluation', column: 'evaluation' },
      { body: 'memo', column: 'memo' },
    ],
  });
};
