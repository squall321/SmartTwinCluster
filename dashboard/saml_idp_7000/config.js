/**
 * SAML IdP Configuration File
 * User database for authentication
 * Auto-generated from YAML config
 */

module.exports = {
  user: {
    "koopark@hpc.local": {
      password: "Soseks314!",
      email: "koopark@hpc.local",
      userName: "koopark",
      firstName: "koopark",
      lastName: "User",
      displayName: "koopark",
      groups: ["DX-Users", "HPC-Admins"],
      department: "General"
    }
  },
  metadata: [
    {id: "email", optional: false, displayName: 'E-Mail Address', description: 'The e-mail address of the user', multiValue: false},
    {id: "userName", optional: false, displayName: 'User Name', description: 'The username of the user', multiValue: false},
    {id: "firstName", optional: false, displayName: 'First Name', description: 'The first name of the user', multiValue: false},
    {id: "lastName", optional: false, displayName: 'Last Name', description: 'The last name of the user', multiValue: false},
    {id: "displayName", optional: true, displayName: 'Display Name', description: 'The display name of the user', multiValue: false},
    {id: "groups", optional: true, displayName: 'Groups', description: 'Group memberships of the user', multiValue: true}
  ]
};
